function quality = AssessHammerRunQuality(T, varargin)
% AssessHammerRunQuality
%
% Computes acquisition and impact-quality indicators for one hammer-test
% table. The function never modifies or rejects the raw data; it marks runs
% that should be excluded from automated modal analysis.

parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, "NumSensors", [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && x > 0 && mod(x, 1) == 0));
addParameter(parser, "Direction", "y", @(x) ischar(x) || isstring(x));
addParameter(parser, "SampleRate", [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "DurationSeconds", [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "Clipping", struct(), @(x) isempty(x) || isstruct(x));
addParameter(parser, "MinimumFiniteFraction", 0.99, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(parser, "MinimumImpactPeakG", 0.02, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "MinimumImpactPeakToNoiseRatio", 8, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "MaximumMissingSampleFraction", 0.002, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(parser, "MaximumGapFactor", 3, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(parser, "MinimumSampleCompleteness", 0.98, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);

parse(parser, varargin{:});

if ~istable(T) || isempty(T)
    error("Input must be a nonempty hammer-test table.");
end

direction = lower(strtrim(string(parser.Results.Direction)));

if ~ismember(direction, ["x", "y", "z"])
    error('Direction must be "x", "y", or "z".');
end

numSensors = parser.Results.NumSensors;

if isempty(numSensors)
    numSensors = inferNumberOfSensors(string(T.Properties.VariableNames), direction);
end

sampleRate = parser.Results.SampleRate;
t = selectElapsedTime(T);

if isempty(sampleRate)
    dtCandidate = median(diff(t), "omitnan");
    sampleRate = 1 / dtCandidate;
end

expectedDt = 1 / sampleRate;
dt = diff(t);
finitePositiveDt = dt(isfinite(dt) & dt > 0);

quality = struct();
quality.usableForAnalysis = true;
quality.messages = strings(0, 1);
quality.warnings = strings(0, 1);
quality.sampleRateExpectedHz = sampleRate;
quality.sampleRateEstimatedHz = NaN;
quality.expectedSamples = NaN;
quality.recordedSamples = height(T);
quality.sampleCompleteness = NaN;
quality.estimatedMissingSamples = NaN;
quality.largeGapCount = NaN;
quality.maximumGapSeconds = NaN;
quality.nonMonotonicTimestampCount = sum(~isfinite(dt) | dt <= 0);
quality.minimumFiniteFraction = NaN;
quality.impactPeakG = NaN;
quality.impactPeakTimeSeconds = NaN;
quality.noiseRMSG = NaN;
quality.impactPeakToNoiseRatio = NaN;
quality.impactDetected = false;
quality.impactEventCount = NaN;
quality.multipleImpactSuspected = false;
quality.hasClipping = false;

if ~isempty(finitePositiveDt)
    quality.sampleRateEstimatedHz = 1 / median(finitePositiveDt);
    quality.maximumGapSeconds = max(finitePositiveDt);
    quality.largeGapCount = sum(finitePositiveDt > ...
        parser.Results.MaximumGapFactor * expectedDt);
    quality.estimatedMissingSamples = sum(max(0, round(finitePositiveDt / expectedDt) - 1));
end

if ~isempty(parser.Results.DurationSeconds)
    quality.expectedSamples = round(parser.Results.DurationSeconds * sampleRate);
    quality.sampleCompleteness = height(T) / max(quality.expectedSamples, 1);
else
    quality.expectedSamples = round((t(end) - t(1)) * sampleRate) + 1;
    quality.sampleCompleteness = height(T) / max(quality.expectedSamples, 1);
end

[signals, finiteFractions] = selectAnalysisSignals(T, numSensors, direction);
quality.minimumFiniteFraction = min(finiteFractions, [], "omitnan");

signals = signals - median(signals, 1, "omitnan");
rowEnergy = sqrt(mean(signals.^2, 2, "omitnan"));
envelopeWindow = max(3, round(0.15 * sampleRate));
impactEnvelope = sqrt(movmean(rowEnergy.^2, envelopeWindow, "omitnan"));
impactEnvelope(~isfinite(impactEnvelope)) = 0;

[quality.impactPeakG, peakIndex] = max(impactEnvelope, [], "omitnan");

if ~isempty(peakIndex) && isfinite(quality.impactPeakG)
    quality.impactPeakTimeSeconds = t(peakIndex);
end

noiseStartIndex = max(1, floor(0.75 * height(T)));
noiseRows = signals(noiseStartIndex:end, :);
quality.noiseRMSG = sqrt(mean(noiseRows.^2, "all", "omitnan"));
quality.impactPeakToNoiseRatio = quality.impactPeakG / max(quality.noiseRMSG, eps);
quality.impactDetected = ...
    quality.impactPeakG >= parser.Results.MinimumImpactPeakG && ...
    quality.impactPeakToNoiseRatio >= parser.Results.MinimumImpactPeakToNoiseRatio;

eventThreshold = max( ...
    0.35 * quality.impactPeakG, ...
    parser.Results.MinimumImpactPeakToNoiseRatio * quality.noiseRMSG);

if isfinite(eventThreshold) && eventThreshold > 0
    [~, eventLocations] = findpeaks(impactEnvelope, ...
        "MinPeakHeight", eventThreshold, ...
        "MinPeakDistance", max(1, round(0.75 * sampleRate)));
    quality.impactEventCount = numel(eventLocations);
    quality.multipleImpactSuspected = quality.impactEventCount > 1;
end

clipping = parser.Results.Clipping;

if ~isempty(clipping) && isfield(clipping, "hasClipping")
    quality.hasClipping = logical(clipping.hasClipping);
end

maximumMissingSamples = max(2, ...
    floor(parser.Results.MaximumMissingSampleFraction * quality.expectedSamples));

if quality.nonMonotonicTimestampCount > 0
    quality = addFailure(quality, "non-monotonic or duplicate sensor timestamps");
end

if ~isfinite(quality.estimatedMissingSamples)
    quality = addFailure(quality, "sample loss could not be assessed");
elseif quality.estimatedMissingSamples > maximumMissingSamples
    quality = addFailure(quality, sprintf( ...
        "estimated missing samples %d exceed limit %d", ...
        quality.estimatedMissingSamples, maximumMissingSamples));
end

if quality.largeGapCount > 0
    quality = addFailure(quality, sprintf( ...
        "%d timestamp gaps exceed %.1f nominal sample intervals", ...
        quality.largeGapCount, parser.Results.MaximumGapFactor));
end

if ~isfinite(quality.sampleCompleteness) || ...
        quality.sampleCompleteness < parser.Results.MinimumSampleCompleteness
    quality = addFailure(quality, sprintf( ...
        "sample completeness %.4f is below %.4f", ...
        quality.sampleCompleteness, parser.Results.MinimumSampleCompleteness));
end

if ~isfinite(quality.minimumFiniteFraction) || ...
        quality.minimumFiniteFraction < parser.Results.MinimumFiniteFraction
    quality = addFailure(quality, sprintf( ...
        "minimum finite-sample fraction %.4f is below %.4f", ...
        quality.minimumFiniteFraction, parser.Results.MinimumFiniteFraction));
end

if ~quality.impactDetected
    quality = addFailure(quality, sprintf( ...
        "impact not detected reliably: peak %.4f g, peak/noise %.2f", ...
        quality.impactPeakG, quality.impactPeakToNoiseRatio));
end

if quality.multipleImpactSuspected
    quality = addWarning(quality, sprintf( ...
        "multiple impacts suspected (%d envelope events)", ...
        quality.impactEventCount));
end

if quality.hasClipping
    quality = addFailure(quality, "accelerometer clipping detected");
end

end

function quality = addWarning(quality, message)

quality.warnings(end + 1, 1) = string(message);

end

function quality = addFailure(quality, message)

quality.usableForAnalysis = false;
quality.messages(end + 1, 1) = string(message);

end

function t = selectElapsedTime(T)

names = string(T.Properties.VariableNames);

if ismember("t_arduino_elapsed_s", names)
    t = double(T.t_arduino_elapsed_s(:));
elseif ismember("t_arduino_s", names)
    t = double(T.t_arduino_s(:) - T.t_arduino_s(1));
elseif ismember("t_arduino_ms", names)
    t = double(T.t_arduino_ms(:) - T.t_arduino_ms(1)) / 1000;
elseif ismember("t_matlab_elapsed_s", names)
    t = double(T.t_matlab_elapsed_s(:));
else
    error("No usable elapsed-time variable was found.");
end

end

function [signals, finiteFractions] = selectAnalysisSignals(T, numSensors, direction)

signals = nan(height(T), numSensors);
finiteFractions = zeros(1, numSensors);

for iSensor = 1:numSensors
    correctedName = sprintf("S%d_a%s_g_corr", iSensor, direction);
    rawName = sprintf("S%d_a%s_g", iSensor, direction);

    if ismember(correctedName, T.Properties.VariableNames) && ...
            any(isfinite(T.(correctedName)))
        values = double(T.(correctedName));
    elseif ismember(rawName, T.Properties.VariableNames)
        values = double(T.(rawName));
    else
        values = nan(height(T), 1);
    end

    signals(:, iSensor) = values;
    finiteFractions(iSensor) = nnz(isfinite(values)) / height(T);
end

end

function numSensors = inferNumberOfSensors(varNames, direction)

pattern = "^S(\d+)_a" + direction + "_g";
tokens = regexp(varNames, pattern, "tokens", "once");
sensorIds = [];

for i = 1:numel(tokens)
    if ~isempty(tokens{i})
        sensorIds(end + 1) = str2double(tokens{i}{1}); %#ok<AGROW>
    end
end

if isempty(sensorIds)
    error("Could not infer sensors from table variable names.");
end

numSensors = max(sensorIds);

end
