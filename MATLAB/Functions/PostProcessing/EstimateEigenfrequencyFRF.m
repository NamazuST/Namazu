function results = EstimateEigenfrequencyFRF(currentSimulationData)
% EstimateEigenfrequencyFRF
%
% Forced-vibration frequency estimation from NAMAZU sensor-rig data.
%
% This function estimates modal/eigenfrequencies by input-output FRF peak
% picking using Welch-based transfer-function estimates.
%
% Expected data source:
%   currentSimulationData.sensorRigData
%
% Expected default columns:
%   t_arduino_elapsed_s
%   S1_ax_g_corr, S2_ax_g_corr, ..., SN_ax_g_corr
%
% Interpretation used here:
%   Sensor 1   = input / base / table acceleration
%   Sensor 2:N = output acceleration channels
%
% If corrected columns do not exist, the function falls back to raw columns:
%   S1_ax_g, S2_ax_g, ...
%
% Output:
%   results.freqHz       identified peak frequencies [Hz]
%   results.zeta         half-power damping estimates [-]
%   results.freqAxis     frequency vector [Hz]
%   results.H            FRFs, one column per output channel
%   results.coherence    input-output coherence
%   results.envFRF       FRF envelope over output channels
%   results.inputSignal  uniformly sampled input acceleration [m/s^2]
%   results.outputAcc    uniformly sampled output accelerations [m/s^2]
%   results.time         uniform time vector [s]
%
% Notes:
%   - Uses x-direction by default.
%   - Assumes the acceleration unit in the table is g.
%   - Converts to m/s^2 before FRF estimation.
%   - Resamples to an equidistant time vector because serial data may have
%     small timestamp jitter.
%   - Requires Signal Processing Toolbox for tfestimate, mscohere, findpeaks.

%% -------------------- USER-ADJUSTABLE DEFAULTS --------------------
g = 9.81;

direction = "x";               % "x", "y", or "z"
inputSensor = 1;               % sensor used as input/base excitation
outputSensors = [];            % empty => use all sensors except inputSensor

useCorrectedSignals = true;    % prefer *_corr columns if available

% Peak-picking parameters
relativePeakLevel = 0.03;      % peak threshold relative to max FRF envelope
minPeakDistanceHz = 15;        % minimum distance between identified peaks
deltaFInterp = 5;              % local interpolation range around each peak [Hz]
fmin = 0.5;                    % lower search frequency [Hz]
fmax = 100;                    % upper search frequency [Hz]

% Plotting
makePlots = true;

%% -------------------- CHECK INPUT DATA --------------------
if ~isprop(currentSimulationData, "sensorRigData") || isempty(currentSimulationData.sensorRigData)
    error("currentSimulationData.sensorRigData does not exist or is empty.");
end

T = currentSimulationData.sensorRigData;

if height(T) < 10
    error("sensorRigData contains too few samples.");
end

varNames = string(T.Properties.VariableNames);

%% -------------------- GET NUMBER OF SENSORS --------------------
if isprop(currentSimulationData, "numberOfAccSensors") && ~isempty(currentSimulationData.numberOfAccSensors)
    NumSens = currentSimulationData.numberOfAccSensors;
else
    NumSens = inferNumberOfSensors(varNames);
end

if NumSens < 2
    error("At least two sensors are required: one input sensor and at least one output sensor.");
end

if isempty(outputSensors)
    outputSensors = setdiff(1:NumSens, inputSensor);
end

%% -------------------- TIME VECTOR --------------------
% Prefer Arduino elapsed time because it is closest to the sampling process.
if ismember("t_arduino_elapsed_s", varNames)
    t = T.t_arduino_elapsed_s;
elseif ismember("t_arduino_s", varNames)
    t = T.t_arduino_s - T.t_arduino_s(1);
elseif ismember("t_matlab_elapsed_s", varNames)
    t = T.t_matlab_elapsed_s;
else
    % Last fallback: use sampleRate if no timestamp is available.
    if isprop(currentSimulationData, "sampleRate") && currentSimulationData.sampleRate > 0
        fs0 = currentSimulationData.sampleRate;
    else
        error("No usable time vector found and no valid sampleRate available.");
    end
    t = (0:height(T)-1).' / fs0;
end

t = double(t(:));

%% -------------------- SELECT INPUT AND OUTPUT CHANNELS --------------------
axisLetter = char(direction);

inputVar = selectAccelerationVariable(varNames, inputSensor, axisLetter, useCorrectedSignals);
input_g = T.(char(inputVar));

outputVars = strings(1, numel(outputSensors));
output_g = nan(height(T), numel(outputSensors));

for k = 1:numel(outputSensors)
    sID = outputSensors(k);
    outputVars(k) = selectAccelerationVariable(varNames, sID, axisLetter, useCorrectedSignals);
    output_g(:,k) = T.(char(outputVars(k)));
end

% Convert from g to m/s^2.
input_signal = double(input_g(:)) * g;
output_acc = double(output_g) * g;

%% -------------------- REMOVE INVALID ROWS --------------------
validRows = isfinite(t) & isfinite(input_signal) & all(isfinite(output_acc), 2);

t = t(validRows);
input_signal = input_signal(validRows);
output_acc = output_acc(validRows,:);

if numel(t) < 20
    error("Too few valid samples after removing NaNs/Infs.");
end

%% -------------------- SORT AND REMOVE DUPLICATE TIME STAMPS --------------------
[t, sortIdx] = sort(t);
input_signal = input_signal(sortIdx);
output_acc = output_acc(sortIdx,:);

[t, uniqueIdx] = unique(t, "stable");
input_signal = input_signal(uniqueIdx);
output_acc = output_acc(uniqueIdx,:);

%% -------------------- RESAMPLE TO UNIFORM TIME GRID --------------------
% tfestimate assumes uniformly sampled data. The Arduino timestamp is close
% to uniform, but serial communication can introduce small timing jitter.
dt = median(diff(t));
fs = 1/dt;

tUniform = (t(1):dt:t(end)).';
inputUniform = interp1(t, input_signal, tUniform, "linear", "extrap");
outputUniform = interp1(t, output_acc, tUniform, "linear", "extrap");

% Remove mean values to avoid a strong DC component.
inputUniform = inputUniform - mean(inputUniform, "omitnan");
outputUniform = outputUniform - mean(outputUniform, 1, "omitnan");

%% -------------------- WELCH / FRF SETTINGS --------------------
N = numel(inputUniform);

if N < 64
    error("Too few samples for FRF estimation.");
end

nfft = 2^nextpow2(N);

windowLength = round(N/8);
windowLength = max(windowLength, 64);
windowLength = min(windowLength, N);

window = hann(windowLength);
noverlap = round(0.5 * windowLength);

nOutputs = size(outputUniform,2);

%% -------------------- ESTIMATE FRFs AND COHERENCE --------------------
H = [];
coh = [];

for ch = 1:nOutputs

    [H(:,ch), freq] = tfestimate( ...
        inputUniform, ...
        outputUniform(:,ch), ...
        window, ...
        noverlap, ...
        nfft, ...
        fs);

    [coh(:,ch), ~] = mscohere( ...
        inputUniform, ...
        outputUniform(:,ch), ...
        window, ...
        noverlap, ...
        nfft, ...
        fs);
end

%% -------------------- FRF ENVELOPE AND PEAK PICKING --------------------
envFRF = max(abs(H), [], 2);

dfFRF = freq(2) - freq(1);

idxSearch = find(freq >= fmin & freq <= fmax);

if isempty(idxSearch)
    error("No frequency samples inside the search range. Check fmin/fmax and sampling rate.");
end

envSearch = envFRF(idxSearch);
maxValue = max(envSearch);

if maxValue <= 0 || isnan(maxValue)
    error("FRF envelope is empty or invalid.");
end

[pks, locsLocal] = findpeaks( ...
    envSearch, ...
    "MinPeakHeight", relativePeakLevel * maxValue, ...
    "MinPeakDistance", round(minPeakDistanceHz / dfFRF));

locs = idxSearch(locsLocal);
nPeaks = numel(pks);

%% -------------------- LOCAL SPLINE REFINEMENT + HALF-POWER DAMPING --------------------
freqv = nan(1,nPeaks);
zeta = nan(1,nPeaks);

npt = round(deltaFInterp / dfFRF);

for iPeak = 1:nPeaks

    idxLeft  = max(locs(iPeak)-npt, 1);
    idxRight = min(locs(iPeak)+npt, numel(freq));

    intFreq = linspace(freq(idxLeft), freq(idxRight), 5000);

    envInterp = spline( ...
        freq(idxLeft:idxRight), ...
        envFRF(idxLeft:idxRight), ...
        intFreq);

    [peakValueInterp, peakIdxInterp] = max(envInterp);

    freqv(iPeak) = intFreq(peakIdxInterp);

    % Half-power bandwidth damping estimate.
    % This is mainly valid for lightly damped, well-separated modes.
    halfPowerLevel = peakValueInterp / sqrt(2);

    leftCandidates = find(envInterp(1:peakIdxInterp) <= halfPowerLevel);

    if isempty(leftCandidates)
        fLeft = NaN;
    else
        il = leftCandidates(end);

        if il < peakIdxInterp
            fLeft = interp1( ...
                envInterp(il:il+1), ...
                intFreq(il:il+1), ...
                halfPowerLevel, ...
                "linear", ...
                "extrap");
        else
            fLeft = NaN;
        end
    end

    rightCandidates = find(envInterp(peakIdxInterp:end) <= halfPowerLevel);

    if isempty(rightCandidates)
        fRight = NaN;
    else
        ir = peakIdxInterp + rightCandidates(1) - 1;

        if ir > peakIdxInterp
            fRight = interp1( ...
                envInterp(ir-1:ir), ...
                intFreq(ir-1:ir), ...
                halfPowerLevel, ...
                "linear", ...
                "extrap");
        else
            fRight = NaN;
        end
    end

    if ~isnan(fLeft) && ~isnan(fRight)
        zeta(iPeak) = (fRight - fLeft) / (2 * freqv(iPeak));
    end
end

%% -------------------- PRINT RESULTS --------------------
fprintf("\nEstimated modal frequencies using FRF peak picking:\n");

if isempty(freqv)
    fprintf("  No peaks found in %.2f Hz to %.2f Hz.\n", fmin, fmax);
else
    for iPeak = 1:numel(freqv)
        fprintf("  Peak %2d: f = %10.5f Hz, zeta = %10.5f\n", ...
            iPeak, freqv(iPeak), zeta(iPeak));
    end
end

%% -------------------- OPTIONAL PLOTS --------------------
if makePlots

    figure;
    tiledlayout(3,1, "TileSpacing", "compact", "Padding", "compact");

    nexttile;
    plot(tUniform, inputUniform, "k");
    grid on;
    xlabel("Time [s]", "Interpreter", "none");
    ylabel("Input acc. [m/s^2]", "Interpreter", "none");
    title(sprintf("Input signal: %s", inputVar), "Interpreter", "none");

    nexttile;
    hold on;
    grid on;
    for ch = 1:nOutputs
        plot(tUniform, outputUniform(:,ch), ...
            "DisplayName", sprintf("Sensor %d", outputSensors(ch)));
    end
    xlabel("Time [s]", "Interpreter", "none");
    ylabel("Output acc. [m/s^2]", "Interpreter", "none");
    title("Output acceleration signals", "Interpreter", "none");
    legend("Location", "best");

    nexttile;
    hold on;
    grid on;
    for ch = 1:nOutputs
        plot(freq, abs(H(:,ch)), ...
            "DisplayName", sprintf("Sensor %d", outputSensors(ch)));
    end
    xlim([0 fmax]);
    xlabel("Frequency [Hz]", "Interpreter", "none");
    ylabel("|H(f)|", "Interpreter", "none");
    title("Input-output FRFs", "Interpreter", "none");
    legend("Location", "best");

    figure;

    subplot(2,1,1);
    plot(freq, envFRF, "k");
    hold on;
    grid on;
    plot(freq(locs), envFRF(locs), "or");
    xlim([0 fmax]);
    xlabel("Frequency [Hz]", "Interpreter", "none");
    ylabel("FRF envelope", "Interpreter", "none");
    title("FRF envelope and identified peaks", "Interpreter", "none");
    legend("FRF envelope", "identified peaks", "Location", "best");

    subplot(2,1,2);
    plot(freq, coh);
    grid on;
    xlim([0 fmax]);
    ylim([0 1]);
    xlabel("Frequency [Hz]", "Interpreter", "none");
    ylabel("Coherence", "Interpreter", "none");
    title("Input-output coherence", "Interpreter", "none");
end

%% -------------------- STORE RESULTS --------------------
results = struct();

results.method = "Forced-vibration FRF peak picking";
results.direction = direction;
results.inputSensor = inputSensor;
results.outputSensors = outputSensors;
results.inputVariable = inputVar;
results.outputVariables = outputVars;

results.freqHz = freqv;
results.zeta = zeta;
results.peakIndices = locs;
results.peakValues = pks;

results.freqAxis = freq;
results.H = H;
results.coherence = coh;
results.envFRF = envFRF;

results.time = tUniform;
results.fs = fs;
results.dt = dt;

results.inputSignal = inputUniform;
results.outputAcc = outputUniform;

results.settings.relativePeakLevel = relativePeakLevel;
results.settings.minPeakDistanceHz = minPeakDistanceHz;
results.settings.deltaFInterp = deltaFInterp;
results.settings.fmin = fmin;
results.settings.fmax = fmax;
results.settings.useCorrectedSignals = useCorrectedSignals;

end

%% ========================================================================
% LOCAL HELPER FUNCTIONS
% ========================================================================

function NumSens = inferNumberOfSensors(varNames)

tokens = regexp(varNames, "^S(\d+)_ax_g", "tokens", "once");
sensorIds = [];

for i = 1:numel(tokens)
    if ~isempty(tokens{i})
        sensorIds(end+1) = str2double(tokens{i}{1}); %#ok<AGROW>
    end
end

if isempty(sensorIds)
    error("Could not infer number of sensors from sensorRigData variable names.");
end

NumSens = max(sensorIds);

end

function varName = selectAccelerationVariable(varNames, sensorIdx, axisLetter, useCorrectedSignals)

if useCorrectedSignals
    correctedName = sprintf("S%d_a%s_g_corr", sensorIdx, axisLetter);

    if ismember(string(correctedName), varNames)
        varName = string(correctedName);
        return;
    end
end

rawName = sprintf("S%d_a%s_g", sensorIdx, axisLetter);

if ismember(string(rawName), varNames)
    varName = string(rawName);
    return;
end

error("Could not find acceleration variable for sensor %d and direction %s.", ...
    sensorIdx, axisLetter);

end
