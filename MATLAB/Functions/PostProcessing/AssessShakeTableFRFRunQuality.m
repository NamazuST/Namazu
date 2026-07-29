function quality = AssessShakeTableFRFRunQuality(T, varargin)
% AssessShakeTableFRFRunQuality
%
% Acquisition and excitation checks for one shaking-table FRF run. Raw
% measurements are never altered or deleted; the returned flag only
% controls whether a run should contribute to the batch modal summary.

parser = inputParser;
parser.FunctionName = mfilename;
addParameter(parser, "NumSensors", 5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && mod(x, 1) == 0);
addParameter(parser, "Direction", "y", @(x) ischar(x) || isstring(x));
addParameter(parser, "SampleRate", 250, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "ExpectedDurationSeconds", [], ...
    @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "AccelerometerRangeG", 8, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "MinimumFiniteFraction", 0.99, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(parser, "MinimumSampleCompleteness", 0.98, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(parser, "MaximumMissingSampleFraction", 0.002, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(parser, "MaximumGapFactor", 3, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(parser, "MinimumBaseRMSG", 0.002, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "NearClippingFraction", 0.95, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
addParameter(parser, "ClippingToleranceG", 0.02, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
parse(parser, varargin{:});

if ~istable(T) || isempty(T)
    error("Input must be a nonempty sensor-rig table.");
end

numSensors = double(parser.Results.NumSensors);
sampleRate = parser.Results.SampleRate;
direction = lower(strtrim(string(parser.Results.Direction)));

if ~ismember(direction, ["x", "y", "z"])
    error('Direction must be "x", "y", or "z".');
end

t = selectElapsedTime(T);
dt = diff(t);
finitePositiveDt = dt(isfinite(dt) & dt > 0);
expectedDt = 1 / sampleRate;

quality = struct();
quality.usableForBatchSummary = true;
quality.messages = strings(0, 1);
quality.warnings = strings(0, 1);
quality.recordedSamples = height(T);
quality.expectedSamples = NaN;
quality.sampleCompleteness = NaN;
quality.actualSampleRateHz = NaN;
quality.estimatedMissingSamples = NaN;
quality.largeGapCount = NaN;
quality.maximumGapSeconds = NaN;
quality.nonMonotonicTimestampCount = sum(~isfinite(dt) | dt <= 0);
quality.minimumFiniteFraction = NaN;
quality.baseRMSG = NaN;
quality.basePeakG = NaN;
quality.nearClipping = false;
quality.hasClipping = false;
quality.maximumRawAbsG = NaN;
quality.peakSensor = NaN;
quality.peakAxis = "";

if ~isempty(finitePositiveDt)
    quality.actualSampleRateHz = 1 / median(finitePositiveDt);
    quality.maximumGapSeconds = max(finitePositiveDt);
    quality.largeGapCount = sum(finitePositiveDt > ...
        parser.Results.MaximumGapFactor * expectedDt);
    quality.estimatedMissingSamples = sum(max(0, ...
        round(finitePositiveDt / expectedDt) - 1));
end

if isempty(parser.Results.ExpectedDurationSeconds)
    quality.expectedSamples = round((t(end) - t(1)) * sampleRate) + 1;
else
    quality.expectedSamples = round( ...
        parser.Results.ExpectedDurationSeconds * sampleRate);
end

quality.sampleCompleteness = height(T) / max(quality.expectedSamples, 1);

[signals, finiteFractions] = selectDirectionSignals(T, numSensors, direction);
quality.minimumFiniteFraction = min(finiteFractions, [], "omitnan");

baseSignal = signals(:, 1);
baseSignal = baseSignal - median(baseSignal, "omitnan");
quality.baseRMSG = sqrt(mean(baseSignal.^2, "omitnan"));
quality.basePeakG = max(abs(baseSignal), [], "omitnan");

[quality.maximumRawAbsG, quality.peakSensor, quality.peakAxis, ...
    nearLimitCount, clippingCount] = summarizeRawRange( ...
        T, numSensors, parser.Results.AccelerometerRangeG, ...
        parser.Results.NearClippingFraction, ...
        parser.Results.ClippingToleranceG);

quality.nearClipping = nearLimitCount > 0;
quality.hasClipping = clippingCount > 0;

maximumMissingSamples = max(2, floor( ...
    parser.Results.MaximumMissingSampleFraction * quality.expectedSamples));

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

if quality.sampleCompleteness < parser.Results.MinimumSampleCompleteness
    quality = addFailure(quality, sprintf( ...
        "sample completeness %.4f is below %.4f", ...
        quality.sampleCompleteness, parser.Results.MinimumSampleCompleteness));
end

if quality.minimumFiniteFraction < parser.Results.MinimumFiniteFraction
    quality = addFailure(quality, sprintf( ...
        "minimum finite-sample fraction %.4f is below %.4f", ...
        quality.minimumFiniteFraction, parser.Results.MinimumFiniteFraction));
end

if ~isfinite(quality.baseRMSG) || ...
        quality.baseRMSG < parser.Results.MinimumBaseRMSG
    quality = addFailure(quality, sprintf( ...
        "sensor 1 base excitation RMS %.5f g is below %.5f g", ...
        quality.baseRMSG, parser.Results.MinimumBaseRMSG));
end

if quality.hasClipping
    quality = addFailure(quality, sprintf( ...
        "accelerometer clipping detected at %.4f g", ...
        quality.maximumRawAbsG));
elseif quality.nearClipping
    quality = addWarning(quality, sprintf( ...
        "acceleration approached full scale: %.4f g", ...
        quality.maximumRawAbsG));
end

end

function quality = addFailure(quality, message)

quality.usableForBatchSummary = false;
quality.messages(end + 1, 1) = string(message);

end

function quality = addWarning(quality, message)

quality.warnings(end + 1, 1) = string(message);

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

function [signals, finiteFractions] = selectDirectionSignals(T, numSensors, direction)

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

function [maximumRawAbsG, peakSensor, peakAxis, nearCount, clippingCount] = ...
    summarizeRawRange(T, numSensors, accelerometerRangeG, ...
        nearClippingFraction, clippingToleranceG)

axes = ["x", "y", "z"];
nearThreshold = nearClippingFraction * accelerometerRangeG;
clipThreshold = accelerometerRangeG - clippingToleranceG;
maximumRawAbsG = NaN;
peakSensor = NaN;
peakAxis = "";
nearCount = 0;
clippingCount = 0;

for iSensor = 1:numSensors
    for iAxis = 1:numel(axes)
        variableName = sprintf("S%d_a%s_g", iSensor, axes(iAxis));

        if ~ismember(variableName, T.Properties.VariableNames)
            continue;
        end

        values = double(T.(variableName));
        channelMaximum = max(abs(values), [], "omitnan");
        nearCount = nearCount + nnz(abs(values) >= nearThreshold);
        clippingCount = clippingCount + nnz(abs(values) >= clipThreshold);

        if ~isfinite(maximumRawAbsG) || channelMaximum > maximumRawAbsG
            maximumRawAbsG = channelMaximum;
            peakSensor = iSensor;
            peakAxis = axes(iAxis);
        end
    end
end

end
