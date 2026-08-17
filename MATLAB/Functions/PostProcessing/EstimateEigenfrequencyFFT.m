function results = EstimateEigenfrequencyFFT(T, varargin)
% EstimateEigenfrequencyFFT
%
% Output-only frequency and damping estimation from NAMAZU sensor-rig table
% data. This is the table-based version of the legacy post-processing
% script that reads separate channel files, computes FFTs, uses an FFT
% envelope for peak picking, and estimates damping from filtered time
% histories.
%
% Expected table columns:
%   t_arduino_elapsed_s, t_arduino_s, or t_matlab_elapsed_s
%   S1_ax_g_corr, S2_ax_g_corr, ...
%
% If corrected columns do not exist, the function falls back to raw columns:
%   S1_ax_g, S2_ax_g, ...
%
% Usage:
%   results = EstimateEigenfrequencyFFT(T);
%   results = EstimateEigenfrequencyFFT(T, "Direction", "z", "SampleRate", 250);
%   results = EstimateEigenfrequencyFFT(T, "Sensors", [1 2 3 4], ...
%       "FMax", 90, "FrequencyResolutionHz", 0.1, "RelativePeakLevel", 0.03);
%   results = EstimateEigenfrequencyFFT(T, ...
%       "PeakInterpolationMethod", "spline");

%% -------------------- SETTINGS --------------------
parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, "Direction", "y", @(x) ischar(x) || isstring(x));
addParameter(parser, "Sensors", [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x > 0)));
addParameter(parser, "UseCorrectedSignals", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "SampleRate", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "UseNominalSampleRate", false, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "Meta", [], @(x) isempty(x) || isstruct(x));
addParameter(parser, "Gravity", 9.81, @(x) isnumeric(x) && isscalar(x) && x > 0);

addParameter(parser, "FMin", 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "FMax", 90, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "FrequencyResolutionHz", [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "RelativePeakLevel", 0.03, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "MinPeakDistanceHz", 10, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "DeltaFInterp", 5, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "PeakInterpolationMethod", "pchip", ...
    @(x) ischar(x) || isstring(x));
addParameter(parser, "SpectrumWindow", "tukey", @(x) ischar(x) || isstring(x));
addParameter(parser, "TukeyAlpha", 0.1, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
addParameter(parser, "MinimumInBandToGlobalPeakRatio", 0.05, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);

addParameter(parser, "DampingSensor", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "DampingStartCycles", 1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "DampingEndCycles", 30, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "DampingMinFitRSquared", 0.5, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
addParameter(parser, "MaximumDampingRatio", 0.2, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);

addParameter(parser, "MakePlots", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "OutputFile", "", @(x) ischar(x) || isstring(x));

parse(parser, varargin{:});

direction = lower(strtrim(string(parser.Results.Direction)));

if ~ismember(direction, ["x", "y", "z"])
    error('Direction must be "x", "y", or "z".');
end

sensors = double(parser.Results.Sensors);
useCorrectedSignals = logical(parser.Results.UseCorrectedSignals);
sampleRateOverride = parser.Results.SampleRate;
useNominalSampleRate = logical(parser.Results.UseNominalSampleRate);
metaOverride = parser.Results.Meta;
g = parser.Results.Gravity;

fmin = parser.Results.FMin;
fmax = parser.Results.FMax;
frequencyResolutionHz = parser.Results.FrequencyResolutionHz;
relativePeakLevel = parser.Results.RelativePeakLevel;
minPeakDistanceHz = parser.Results.MinPeakDistanceHz;
deltaFInterp = parser.Results.DeltaFInterp;
peakInterpolationMethod = lower(strtrim( ...
    string(parser.Results.PeakInterpolationMethod)));
spectrumWindowName = lower(strtrim(string(parser.Results.SpectrumWindow)));
tukeyAlpha = parser.Results.TukeyAlpha;
minimumInBandToGlobalPeakRatio = parser.Results.MinimumInBandToGlobalPeakRatio;

if ~ismember(spectrumWindowName, ["rectangular", "tukey"])
    error('SpectrumWindow must be "rectangular" or "tukey".');
end

if ~ismember(peakInterpolationMethod, ["pchip", "spline"])
    error('PeakInterpolationMethod must be "pchip" or "spline".');
end

dampingSensor = parser.Results.DampingSensor;
dampingStartCycles = parser.Results.DampingStartCycles;
dampingEndCycles = parser.Results.DampingEndCycles;
dampingMinFitRSquared = parser.Results.DampingMinFitRSquared;
maximumDampingRatio = parser.Results.MaximumDampingRatio;

makePlots = logical(parser.Results.MakePlots);
outputFile = string(parser.Results.OutputFile);

if dampingEndCycles <= dampingStartCycles
    error("DampingEndCycles must be larger than DampingStartCycles.");
end

if fmax <= fmin
    error("FMax must be larger than FMin.");
end

%% -------------------- CHECK INPUT TABLE --------------------
if nargin < 1 || isempty(T) || ~istable(T)
    error("Input must be the sensor-rig measurement table T.");
end

if height(T) < 10
    error("T contains too few samples.");
end

varNames = string(T.Properties.VariableNames);

sourceSampleRate = readSampleRateFromTable(T);
sourceNumSens = readNumberOfSensorsFromTable(T);

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

if isempty(sensors)
    if ~isempty(sourceNumSens)
        sensors = 1:sourceNumSens;
    else
        sensors = inferNumberOfSensors(varNames, direction);
    end
end

sensors = double(sensors(:).');
validateattributes(sensors, {'numeric'}, {'vector', 'integer', 'positive'}, mfilename, 'Sensors');

%% -------------------- TIME AND CHANNEL SELECTION --------------------
[t, sourceSampleRate] = selectTimeVector(T, sourceSampleRate, sampleRateOverride);

channelVars = strings(1, numel(sensors));
acc_g = nan(height(T), numel(sensors));

for iCh = 1:numel(sensors)
    channelVars(iCh) = selectAccelerationVariable( ...
        varNames, sensors(iCh), char(direction), useCorrectedSignals);
    acc_g(:, iCh) = T.(char(channelVars(iCh)));
end

acc = double(acc_g) * g;

validRows = isfinite(t) & all(isfinite(acc), 2);
t = double(t(validRows));
acc = acc(validRows, :);

if numel(t) < 20
    error("Too few valid samples after removing NaNs/Infs.");
end

[t, sortIdx] = sort(t);
acc = acc(sortIdx, :);

[t, uniqueIdx] = unique(t, "stable");
acc = acc(uniqueIdx, :);

%% -------------------- RESAMPLE TO UNIFORM GRID --------------------
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

fs = 1 / dt;
fNyquist = fs / 2;

if fmax > fNyquist
    error("FMax %.2f Hz is above the Nyquist frequency %.2f Hz. Use sampleRate > %.2f Hz or lower FMax.", ...
        fmax, fNyquist, 2*fmax);
end

tUniform = (t(1):dt:t(end)).';
accUniform = interp1(t, acc, tUniform, "linear", "extrap");
accUniform = accUniform - mean(accUniform, 1, "omitnan");

nSamples = size(accUniform, 1);

if nSamples < 64
    error("Too few samples for FFT-based estimation.");
end

measurementDuration = tUniform(end) - tUniform(1);
nFFT = nSamples;

if ~isempty(frequencyResolutionHz)
    nFFT = max(nSamples, ceil(fs / frequencyResolutionHz));
    nFFT = 2^nextpow2(nFFT);
end

df = fs / nFFT;

%% -------------------- FFT AND PEAK PICKING --------------------
if spectrumWindowName == "tukey"
    spectrumWindow = tukeywin(nSamples, tukeyAlpha);
else
    spectrumWindow = ones(nSamples, 1);
end

accForFFT = accUniform .* spectrumWindow;
coherentAmplitudeScale = sum(spectrumWindow) / 2;
fftFull = fft(accForFFT, nFFT);
fftScaled = fftFull / coherentAmplitudeScale;

nFreq = floor(nFFT/2) + 1;
freq = (0:nFreq-1).' * df;
accFFT = fftScaled(1:nFreq, :);
accFFTAbs = abs(accFFT);

[envFFT, envChannelIdx] = max(accFFTAbs, [], 2);

idxSearch = find(freq >= fmin & freq <= fmax);

if isempty(idxSearch)
    error("No frequency samples inside the search range. Check fmin/fmax and sampling rate.");
end

envSearch = envFFT(idxSearch);
maxValue = max(envSearch);

if maxValue <= 0 || isnan(maxValue)
    error("FFT envelope is empty or invalid.");
end

idxGlobal = freq >= fmin & freq <= fNyquist;
globalMaxValue = max(envFFT(idxGlobal));
inBandToGlobalPeakRatio = maxValue / globalMaxValue;

if ~isfinite(inBandToGlobalPeakRatio) || ...
        inBandToGlobalPeakRatio < minimumInBandToGlobalPeakRatio
    error("EstimateEigenfrequencyFFT:EnergyOutsideSearchRange", ...
        "Dominant spectral energy lies outside FMin/FMax: in-band/global peak ratio %.4f is below %.4f.", ...
        inBandToGlobalPeakRatio, minimumInBandToGlobalPeakRatio);
end

[pks, locsLocal] = findpeaks( ...
    envSearch, ...
    "MinPeakHeight", relativePeakLevel * maxValue, ...
    "MinPeakDistance", max(1, round(minPeakDistanceHz / df)));

locs = idxSearch(locsLocal);
nPeaks = numel(pks);

freqv = nan(1, nPeaks);
peakValuesRefined = nan(1, nPeaks);
peakSensor = nan(1, nPeaks);
peakChannel = nan(1, nPeaks);
npt = max(1, round(deltaFInterp / df));

for iPeak = 1:nPeaks
    idxLeft = max(locs(iPeak) - npt, idxSearch(1));
    idxRight = min(locs(iPeak) + npt, idxSearch(end));

    if idxRight <= idxLeft
        freqv(iPeak) = freq(locs(iPeak));
        peakValuesRefined(iPeak) = envFFT(locs(iPeak));
    else
        intFreq = linspace(freq(idxLeft), freq(idxRight), 5000);
        envInterp = interp1( ...
            freq(idxLeft:idxRight), ...
            envFFT(idxLeft:idxRight), ...
            intFreq, ...
            peakInterpolationMethod);
        [peakValuesRefined(iPeak), peakIdxInterp] = max(envInterp);
        freqv(iPeak) = intFreq(peakIdxInterp);
    end

    freqv(iPeak) = min(max(freqv(iPeak), fmin), fmax);

    peakChannel(iPeak) = envChannelIdx(locs(iPeak));
    peakSensor(iPeak) = sensors(peakChannel(iPeak));
end

%% -------------------- DAMPING ESTIMATION --------------------
zeta = nan(1, nPeaks);
dampingLambda = nan(1, nPeaks);
dampingSensorUsed = nan(1, nPeaks);
dampingChannelUsed = nan(1, nPeaks);
dampingTime = cell(1, nPeaks);
dampingSignal = cell(1, nPeaks);
dampingEnvelope = cell(1, nPeaks);
dampingEnvelopeFit = cell(1, nPeaks);
dampingFitRSquared = nan(1, nPeaks);
dampingFitStatus = repmat("not evaluated", 1, nPeaks);

fftFullDamping = fft(accUniform);
freqFullDamping = (0:nSamples-1).' * fs / nSamples;
freqSignedDamping = freqFullDamping;
freqSignedDamping(freqFullDamping > fNyquist) = ...
    freqSignedDamping(freqFullDamping > fNyquist) - fs;

for iPeak = 1:nPeaks
    if ~isfinite(freqv(iPeak)) || freqv(iPeak) <= 0
        dampingFitStatus(iPeak) = "invalid modal frequency";
        continue;
    end

    if isempty(dampingSensor)
        iChannel = peakChannel(iPeak);
    else
        iChannel = find(sensors == dampingSensor, 1);

        if isempty(iChannel)
            error("DampingSensor %d is not included in Sensors.", dampingSensor);
        end
    end

    dampingChannelUsed(iPeak) = iChannel;
    dampingSensorUsed(iPeak) = sensors(iChannel);

    bandMask = abs(abs(freqSignedDamping) - freqv(iPeak)) <= deltaFInterp;

    if ~any(bandMask)
        nPositiveDamping = floor(nSamples/2) + 1;
        [~, idxNearestPositive] = min(abs(freqFullDamping(1:nPositiveDamping) - freqv(iPeak)));
        bandMask(idxNearestPositive) = true;

        idxMirror = nSamples - idxNearestPositive + 2;

        if idxNearestPositive > 1 && idxMirror <= nSamples
            bandMask(idxMirror) = true;
        end
    end

    accFilt = real(ifft(fftFullDamping(:, iChannel) .* bandMask));
    [~, idxMax] = max(abs(accFilt));

    idxStart = idxMax + round((dampingStartCycles / freqv(iPeak)) * fs);
    idxEnd = idxMax + round((dampingEndCycles / freqv(iPeak)) * fs);

    idxStart = max(1, min(idxStart, nSamples));
    idxEnd = max(1, min(idxEnd, nSamples));

    minSamples = max(10, round(fs / freqv(iPeak)));
    if idxEnd - idxStart + 1 < minSamples
        dampingFitStatus(iPeak) = "insufficient decay segment";
        continue;
    end

    segment = accFilt(idxStart:idxEnd);
    tSegment = tUniform(idxStart:idxEnd);
    tFit = tSegment - tSegment(1);

    envSegment = abs(hilbert(segment));
    smoothWindow = max(3, round(0.25 * fs / freqv(iPeak)));
    envSegment = smoothdata(envSegment, "movmean", smoothWindow);

    validEnv = isfinite(envSegment) & envSegment > 0 & isfinite(tFit);

    if nnz(validEnv) < 5
        dampingFitStatus(iPeak) = "insufficient finite envelope samples";
        continue;
    end

    coeff = polyfit(tFit(validEnv), log(envSegment(validEnv)), 1);
    envFit = exp(polyval(coeff, tFit));

    dampingTime{iPeak} = tSegment;
    dampingSignal{iPeak} = segment;
    dampingEnvelope{iPeak} = envSegment;
    dampingEnvelopeFit{iPeak} = envFit;

    logEnvelope = log(envSegment(validEnv));
    logEnvelopeFit = polyval(coeff, tFit(validEnv));
    residualSumSquares = sum((logEnvelope - logEnvelopeFit).^2);
    totalSumSquares = sum((logEnvelope - mean(logEnvelope)).^2);

    if totalSumSquares > 0
        dampingFitRSquared(iPeak) = 1 - residualSumSquares / totalSumSquares;
    end

    if coeff(1) >= 0
        dampingFitStatus(iPeak) = "non-decaying envelope";
        continue;
    end

    if ~isfinite(dampingFitRSquared(iPeak)) || ...
            dampingFitRSquared(iPeak) < dampingMinFitRSquared
        dampingFitStatus(iPeak) = "poor exponential fit";
        continue;
    end

    lambda = -coeff(1);
    zetaCandidate = lambda / (2*pi*freqv(iPeak));

    if ~isfinite(zetaCandidate) || zetaCandidate <= 0 || ...
            zetaCandidate > maximumDampingRatio
        dampingFitStatus(iPeak) = "damping ratio outside accepted range";
        continue;
    end

    dampingLambda(iPeak) = lambda;
    zeta(iPeak) = zetaCandidate;
    dampingFitStatus(iPeak) = "accepted";
end

%% -------------------- PRINT AND OPTIONAL FILE OUTPUT --------------------
fprintf("\nEstimated modal frequencies using FFT envelope peak picking:\n");

if isempty(freqv)
    fprintf("  No peaks found in %.2f Hz to %.2f Hz.\n", fmin, fmax);
else
    for iPeak = 1:numel(freqv)
        fprintf("  Peak %2d: f = %10.5f Hz, zeta = %10.5f, sensor = %d\n", ...
            iPeak, freqv(iPeak), zeta(iPeak), dampingSensorUsed(iPeak));
    end
end

if strlength(outputFile) > 0
    writeResultsFile(outputFile, freqv, zeta, dampingSensorUsed);
end

%% -------------------- PLOTS --------------------
if makePlots
    plotFFTResults( ...
        tUniform, ...
        accUniform, ...
        freq, ...
        accFFTAbs, ...
        envFFT, ...
        locs, ...
        sensors, ...
        channelVars, ...
        freqv, ...
        zeta, ...
        dampingTime, ...
        dampingSignal, ...
        dampingEnvelope, ...
        dampingEnvelopeFit, ...
        fmax);
end

%% -------------------- STORE RESULTS --------------------
results = struct();

results.method = "Output-only FFT envelope peak picking";
results.direction = direction;
results.sensors = sensors;
results.channelVariables = channelVars;

results.freqHz = freqv;
results.zeta = zeta;
results.dampingLambda = dampingLambda;
results.peakIndices = locs;
results.peakValues = pks;
results.peakValuesRefined = peakValuesRefined;
results.peakSensor = peakSensor;
results.dampingSensor = dampingSensorUsed;

results.time = tUniform;
results.acceleration = accUniform;
results.accelerationForFFT = accForFFT;
results.rms = sqrt(mean(accUniform.^2, 1, "omitnan"));

results.freqAxis = freq;
results.fft = accFFT;
results.fftAbs = accFFTAbs;
results.envFFT = envFFT;
results.spectrumWindow = spectrumWindow;

results.dampingTime = dampingTime;
results.dampingSignal = dampingSignal;
results.dampingEnvelope = dampingEnvelope;
results.dampingEnvelopeFit = dampingEnvelopeFit;
results.dampingFitRSquared = dampingFitRSquared;
results.dampingFitStatus = dampingFitStatus;

results.fs = fs;
results.dt = dt;
results.df = df;
results.measurementDuration = measurementDuration;

results.settings.fmin = fmin;
results.settings.fmax = fmax;
results.settings.frequencyResolutionHz = frequencyResolutionHz;
results.settings.relativePeakLevel = relativePeakLevel;
results.settings.minPeakDistanceHz = minPeakDistanceHz;
results.settings.deltaFInterp = deltaFInterp;
results.settings.peakInterpolationMethod = peakInterpolationMethod;
results.settings.spectrumWindow = spectrumWindowName;
results.settings.tukeyAlpha = tukeyAlpha;
results.settings.minimumInBandToGlobalPeakRatio = minimumInBandToGlobalPeakRatio;
results.settings.inBandToGlobalPeakRatio = inBandToGlobalPeakRatio;
results.settings.useCorrectedSignals = useCorrectedSignals;
results.settings.sampleRateOverride = sampleRateOverride;
results.settings.useNominalSampleRate = useNominalSampleRate;
results.settings.nominalSampleRate = nominalSampleRate;
results.settings.fNyquist = fNyquist;
results.settings.nSamples = nSamples;
results.settings.nFFT = nFFT;
results.settings.dampingStartCycles = dampingStartCycles;
results.settings.dampingEndCycles = dampingEndCycles;
results.settings.dampingMinFitRSquared = dampingMinFitRSquared;
results.settings.maximumDampingRatio = maximumDampingRatio;

end

%% ========================================================================
% LOCAL HELPER FUNCTIONS
% ========================================================================

function sampleRate = readSampleRateFromTable(T)

sampleRate = [];

if ~isstruct(T.Properties.UserData) || ~isfield(T.Properties.UserData, "sampleRate")
    return;
end

candidate = T.Properties.UserData.sampleRate;

if isnumeric(candidate) && isscalar(candidate) && candidate > 0
    sampleRate = candidate;
end

end

function numberOfSensors = readNumberOfSensorsFromTable(T)

numberOfSensors = [];

if ~isstruct(T.Properties.UserData) || ~isfield(T.Properties.UserData, "numberOfSensors")
    return;
end

candidate = T.Properties.UserData.numberOfSensors;

if isnumeric(candidate) && isscalar(candidate) && candidate > 0
    numberOfSensors = candidate;
end

end

function sensors = inferNumberOfSensors(varNames, direction)

pattern = "^S(\d+)_a" + direction + "_g";
tokens = regexp(varNames, pattern, "tokens", "once");
sensorIds = [];

for i = 1:numel(tokens)
    if ~isempty(tokens{i})
        sensorIds(end+1) = str2double(tokens{i}{1}); %#ok<AGROW>
    end
end

if isempty(sensorIds)
    error("Could not infer sensors from table variable names.");
end

sensors = 1:max(sensorIds);

end

function [t, sourceSampleRate] = selectTimeVector(T, sourceSampleRate, sampleRateOverride)

varNames = string(T.Properties.VariableNames);

if ismember("t_arduino_elapsed_s", varNames)
    t = T.t_arduino_elapsed_s;
elseif ismember("t_arduino_s", varNames)
    t = T.t_arduino_s - T.t_arduino_s(1);
elseif ismember("t_matlab_elapsed_s", varNames)
    t = T.t_matlab_elapsed_s;
else
    if ~isempty(sampleRateOverride)
        fs0 = sampleRateOverride;
    elseif ~isempty(sourceSampleRate)
        fs0 = sourceSampleRate;
    else
        error("No usable time vector found and no valid sampleRate available.");
    end

    t = (0:height(T)-1).' / fs0;

    if isempty(sourceSampleRate)
        sourceSampleRate = fs0;
    end
end

t = double(t(:));

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

function writeResultsFile(outputFile, freqv, zeta, dampingSensorUsed)

fid = fopen(outputFile, "w");

if fid < 0
    error("Could not open output file %s.", outputFile);
end

cleanupObj = onCleanup(@() fclose(fid));

fprintf(fid, "peak,frequency_hz,zeta,damping_sensor\n");

for iPeak = 1:numel(freqv)
    fprintf(fid, "%d,%+.8f,%+.8f,%d\n", ...
        iPeak, freqv(iPeak), zeta(iPeak), dampingSensorUsed(iPeak));
end

end

function plotFFTResults(t, acc, freq, accFFTAbs, envFFT, locs, sensors, channelVars, ...
    freqv, zeta, dampingTime, dampingSignal, dampingEnvelope, dampingEnvelopeFit, fmax)

nChannels = numel(sensors);

figure;
tiledlayout(nChannels, 1, "TileSpacing", "compact", "Padding", "compact");

for iCh = 1:nChannels
    nexttile;
    plot(t, acc(:, iCh));
    grid on;
    xlabel("Time [s]", "Interpreter", "none");
    ylabel("Acceleration [m/s^2]", "Interpreter", "none");
    title(sprintf("Sensor %d: %s", sensors(iCh), channelVars(iCh)), "Interpreter", "none");
end

figure;
tiledlayout(nChannels + 1, 1, "TileSpacing", "compact", "Padding", "compact");

for iCh = 1:nChannels
    nexttile;
    plot(freq, accFFTAbs(:, iCh));
    grid on;
    xlim([0 fmax]);
    xlabel("f [Hz]", "Interpreter", "none");
    ylabel("|FFT| [m/s^2]", "Interpreter", "none");
    title(sprintf("FFT sensor %d", sensors(iCh)), "Interpreter", "none");
end

nexttile;
plot(freq, envFFT, "-k");
hold on;
grid on;

if ~isempty(locs)
    plot(freq(locs), envFFT(locs), "or");
end

xlim([0 fmax]);
xlabel("f [Hz]", "Interpreter", "none");
ylabel("FFT envelope [m/s^2]", "Interpreter", "none");
title("FFT envelope and identified peaks", "Interpreter", "none");
legend("FFT envelope", "peak", "Location", "best");

if isempty(freqv)
    return;
end

figure;
nPeaks = numel(freqv);
tiledlayout(nPeaks, 1, "TileSpacing", "compact", "Padding", "compact");

for iPeak = 1:nPeaks
    nexttile;

    if isempty(dampingTime{iPeak})
        title(sprintf("Peak %.3f Hz: damping estimate unavailable", freqv(iPeak)), ...
            "Interpreter", "none");
        grid on;
        continue;
    end

    plot(dampingTime{iPeak}, dampingSignal{iPeak}, "-k");
    hold on;
    plot(dampingTime{iPeak}, dampingEnvelope{iPeak}, "-b");
    plot(dampingTime{iPeak}, dampingEnvelopeFit{iPeak}, "-r");
    grid on;
    xlabel("Time [s]", "Interpreter", "none");
    ylabel("Filtered acceleration [m/s^2]", "Interpreter", "none");
    title(sprintf("Peak %.3f Hz, zeta %.5f", freqv(iPeak), zeta(iPeak)), ...
        "Interpreter", "none");
    legend("filtered", "envelope", "fit", "Location", "best");
end

end
