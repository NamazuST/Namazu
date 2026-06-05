function results = EstimateEigenfrequencyFRF(dataSource, varargin)
% EstimateEigenfrequencyFRF
%
% Forced-vibration frequency estimation from NAMAZU sensor-rig data.
%
% This function estimates modal/eigenfrequencies by input-output FRF peak
% picking using Welch-based transfer-function estimates.
%
% Expected data source:
%   currentSimulationData.sensorRigData
%   or the sensorRigData table T directly
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
%   - Uses y-direction by default.
%   - Assumes the acceleration unit in the table is g.
%   - Converts to m/s^2 before FRF estimation.
%   - Resamples to an equidistant time vector because serial data may have
%     small timestamp jitter.
%   - Requires Signal Processing Toolbox for tfestimate, mscohere, findpeaks.
%
% Usage:
%   results = EstimateEigenfrequencyFRF(currentSimulationData);
%   results = EstimateEigenfrequencyFRF(T);
%   results = EstimateEigenfrequencyFRF(T, "Direction", "z", ...
%       "SampleRate", 250, "FMax", 100, "FrequencyResolutionHz", 0.25);
%   results = EstimateEigenfrequencyFRF(T, "Meta", meta);

%% -------------------- USER-ADJUSTABLE DEFAULTS --------------------
parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, "Direction", "y", @(x) ischar(x) || isstring(x));
addParameter(parser, "InputSensor", 1, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "OutputSensors", [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x > 0)));
addParameter(parser, "UseCorrectedSignals", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "RelativePeakLevel", 0.03, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "MinPeakDistanceHz", 15, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "DeltaFInterp", 5, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "FMin", 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "FMax", 100, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "MakePlots", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "SampleRate", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "NumberOfSensors", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "Gravity", 9.81, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "UseNominalSampleRate", false, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "FrequencyResolutionHz", 0.25, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "WindowDurationSeconds", 8, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "Meta", [], @(x) isempty(x) || isstruct(x));
parse(parser, varargin{:});

g = parser.Results.Gravity;

direction = lower(strtrim(string(parser.Results.Direction)));

if ~ismember(direction, ["x", "y", "z"])
    error('Direction must be "x", "y", or "z".');
end

inputSensor = double(parser.Results.InputSensor);
validateattributes(inputSensor, {'numeric'}, {'scalar', 'integer', 'positive'}, mfilename, 'InputSensor');

outputSensors = double(parser.Results.OutputSensors);
if ~isempty(outputSensors)
    validateattributes(outputSensors, {'numeric'}, {'vector', 'integer', 'positive'}, mfilename, 'OutputSensors');
end

useCorrectedSignals = logical(parser.Results.UseCorrectedSignals);

relativePeakLevel = parser.Results.RelativePeakLevel;
minPeakDistanceHz = parser.Results.MinPeakDistanceHz;
deltaFInterp = parser.Results.DeltaFInterp;
fmin = parser.Results.FMin;
fmax = parser.Results.FMax;
makePlots = logical(parser.Results.MakePlots);
sampleRateOverride = parser.Results.SampleRate;
numberOfSensorsOverride = parser.Results.NumberOfSensors;
useNominalSampleRate = logical(parser.Results.UseNominalSampleRate);
frequencyResolutionHz = parser.Results.FrequencyResolutionHz;
windowDurationSeconds = parser.Results.WindowDurationSeconds;
metaOverride = parser.Results.Meta;

%% -------------------- CHECK INPUT DATA --------------------
if nargin < 1 || isempty(dataSource)
    error("Provide either currentSimulationData or the sensorRigData table T.");
end

[T, sourceSampleRate, sourceNumSens] = unpackSensorRigData(dataSource);

if ~isempty(metaOverride)
    if isfield(metaOverride, "sampleRate") && ...
            isnumeric(metaOverride.sampleRate) && metaOverride.sampleRate > 0
        sourceSampleRate = metaOverride.sampleRate;
    end

    if isfield(metaOverride, "numSensors") && ...
            isnumeric(metaOverride.numSensors) && metaOverride.numSensors > 0
        sourceNumSens = metaOverride.numSensors;
    end
end

if height(T) < 10
    error("sensorRigData contains too few samples.");
end

varNames = string(T.Properties.VariableNames);

%% -------------------- GET NUMBER OF SENSORS --------------------
if ~isempty(numberOfSensorsOverride)
    NumSens = numberOfSensorsOverride;
elseif ~isempty(sourceNumSens)
    NumSens = sourceNumSens;
else
    NumSens = inferNumberOfSensors(varNames);
end

NumSens = double(NumSens);
validateattributes(NumSens, {'numeric'}, {'scalar', 'integer', 'positive'}, mfilename, 'NumberOfSensors');

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
    if ~isempty(sampleRateOverride)
        fs0 = sampleRateOverride;
    elseif ~isempty(sourceSampleRate)
        fs0 = sourceSampleRate;
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
nominalSampleRate = [];

if ~isempty(sampleRateOverride)
    nominalSampleRate = sampleRateOverride;
elseif ~isempty(sourceSampleRate)
    nominalSampleRate = sourceSampleRate;
end

if useNominalSampleRate && ~isempty(nominalSampleRate)
    dt = 1 / nominalSampleRate;
else
    dt = median(diff(t));
end

fs = 1/dt;
fNyquist = fs / 2;

if fmax > fNyquist
    error("FMax %.2f Hz is above the Nyquist frequency %.2f Hz. Use sampleRate > %.2f Hz or lower FMax.", ...
        fmax, fNyquist, 2*fmax);
end

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

if isempty(windowDurationSeconds)
    windowLength = round(N/8);
else
    windowLength = round(windowDurationSeconds * fs);
end

windowLength = max(windowLength, min(64, N));
windowLength = min(windowLength, N);

minNfftForResolution = ceil(fs / frequencyResolutionHz);
nfft = 2^nextpow2(max(windowLength, minNfftForResolution));

window = hann(windowLength);
noverlap = round(0.5 * windowLength);

nOutputs = size(outputUniform,2);

%% -------------------- ESTIMATE FRFs AND COHERENCE --------------------
nFreq = floor(nfft/2) + 1;
H = complex(nan(nFreq, nOutputs));
coh = nan(nFreq, nOutputs);
freq = nan(nFreq, 1);

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
    "MinPeakDistance", max(1, round(minPeakDistanceHz / dfFRF)));

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
results.settings.sampleRateOverride = sampleRateOverride;
results.settings.numberOfSensorsOverride = numberOfSensorsOverride;
results.settings.useNominalSampleRate = useNominalSampleRate;
results.settings.nominalSampleRate = nominalSampleRate;
results.settings.frequencyResolutionHz = frequencyResolutionHz;
results.settings.actualFrequencySpacingHz = dfFRF;
results.settings.fNyquist = fNyquist;
results.settings.nfft = nfft;
results.settings.windowLength = windowLength;
results.settings.windowDurationSeconds = windowLength / fs;
results.settings.overlapLength = noverlap;

end

%% ========================================================================
% LOCAL HELPER FUNCTIONS
% ========================================================================

function [T, sourceSampleRate, sourceNumSens] = unpackSensorRigData(dataSource)

sourceSampleRate = [];
sourceNumSens = [];

if istable(dataSource)
    T = dataSource;
    [sourceSampleRate, sourceNumSens] = readSensorTableUserData(T);
    return;
end

if ~hasFieldOrProperty(dataSource, "sensorRigData")
    error("Input must be a sensorRigData table or an object/struct with a sensorRigData field.");
end

T = getFieldOrProperty(dataSource, "sensorRigData");

if isempty(T) || ~istable(T)
    error("sensorRigData does not exist, is empty, or is not a table.");
end

[tableSampleRate, tableNumSens] = readSensorTableUserData(T);

if hasFieldOrProperty(dataSource, "sampleRate")
    sourceSampleRate = getFieldOrProperty(dataSource, "sampleRate");

    if isempty(sourceSampleRate) || ~isnumeric(sourceSampleRate) || sourceSampleRate <= 0
        sourceSampleRate = [];
    end
end

if isempty(sourceSampleRate)
    sourceSampleRate = tableSampleRate;
end

if hasFieldOrProperty(dataSource, "numberOfAccSensors")
    sourceNumSens = getFieldOrProperty(dataSource, "numberOfAccSensors");

    if isempty(sourceNumSens) || ~isnumeric(sourceNumSens) || sourceNumSens <= 0
        sourceNumSens = [];
    end
end

if isempty(sourceNumSens)
    sourceNumSens = tableNumSens;
end

end

function [sourceSampleRate, sourceNumSens] = readSensorTableUserData(T)

sourceSampleRate = [];
sourceNumSens = [];

if ~isstruct(T.Properties.UserData) || ~isfield(T.Properties.UserData, "sampleRate")
    return;
end

sampleRate = T.Properties.UserData.sampleRate;

if isnumeric(sampleRate) && isscalar(sampleRate) && sampleRate > 0
    sourceSampleRate = sampleRate;
end

if isfield(T.Properties.UserData, "numberOfSensors")
    numberOfSensors = T.Properties.UserData.numberOfSensors;

    if isnumeric(numberOfSensors) && isscalar(numberOfSensors) && numberOfSensors > 0
        sourceNumSens = numberOfSensors;
    end
end

end

function tf = hasFieldOrProperty(dataSource, name)

if isstruct(dataSource)
    tf = isfield(dataSource, char(name));
elseif isobject(dataSource)
    tf = isprop(dataSource, char(name));
else
    tf = false;
end

end

function value = getFieldOrProperty(dataSource, name)

value = dataSource.(char(name));

end

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
