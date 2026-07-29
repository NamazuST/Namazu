function peak = SummarizeHammerTimeHistoryPeak(T, varargin)
% SummarizeHammerTimeHistoryPeak
%
% Reports the largest instantaneous acceleration in one measurement
% direction. Both raw and baseline-corrected values are retained. The
% corrected signal is selected as the primary time-history peak when it is
% available.

parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, "NumSensors", [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && x > 0 && mod(x, 1) == 0));
addParameter(parser, "Direction", "y", @(x) ischar(x) || isstring(x));

parse(parser, varargin{:});

if ~istable(T) || isempty(T)
    error("Input must be a nonempty hammer-test table.");
end

direction = lower(strtrim(string(parser.Results.Direction)));

if ~ismember(direction, ["x", "y", "z", "mag"])
    error('Direction must be "x", "y", "z", or "mag".');
end

numSensors = parser.Results.NumSensors;

if isempty(numSensors)
    numSensors = inferNumberOfSensors(string(T.Properties.VariableNames));
end

Sensor = (1:numSensors).';
RawMinG = nan(numSensors, 1);
RawMaxG = nan(numSensors, 1);
RawMaxAbsG = nan(numSensors, 1);
RawSignedPeakG = nan(numSensors, 1);
RawPeakTimeSeconds = nan(numSensors, 1);
CorrectedMinG = nan(numSensors, 1);
CorrectedMaxG = nan(numSensors, 1);
CorrectedMaxAbsG = nan(numSensors, 1);
CorrectedSignedPeakG = nan(numSensors, 1);
CorrectedPeakTimeSeconds = nan(numSensors, 1);
t = selectTimeHistoryTime(T);

for iSensor = 1:numSensors
    if direction == "mag"
        rawName = sprintf("S%d_mag_g", iSensor);
        correctedName = sprintf("S%d_mag_g_corr", iSensor);
    else
        rawName = sprintf("S%d_a%s_g", iSensor, direction);
        correctedName = sprintf("S%d_a%s_g_corr", iSensor, direction);
    end

    if ismember(rawName, T.Properties.VariableNames)
        raw = double(T.(rawName));
        RawMinG(iSensor) = min(raw, [], "omitnan");
        RawMaxG(iSensor) = max(raw, [], "omitnan");
        [RawMaxAbsG(iSensor), RawSignedPeakG(iSensor), RawPeakTimeSeconds(iSensor)] = ...
            findTimeHistoryPeak(raw, t);
    end

    if ismember(correctedName, T.Properties.VariableNames)
        corrected = double(T.(correctedName));
        CorrectedMinG(iSensor) = min(corrected, [], "omitnan");
        CorrectedMaxG(iSensor) = max(corrected, [], "omitnan");
        [CorrectedMaxAbsG(iSensor), CorrectedSignedPeakG(iSensor), ...
            CorrectedPeakTimeSeconds(iSensor)] = findTimeHistoryPeak(corrected, t);
    end
end

peak = struct();
peak.direction = direction;
peak.perSensor = table( ...
    Sensor, ...
    RawMinG, ...
    RawMaxG, ...
    RawMaxAbsG, ...
    RawSignedPeakG, ...
    RawPeakTimeSeconds, ...
    CorrectedMinG, ...
    CorrectedMaxG, ...
    CorrectedMaxAbsG, ...
    CorrectedSignedPeakG, ...
    CorrectedPeakTimeSeconds);

[peak.rawMaxAbsG, rawRow] = max(RawMaxAbsG, [], "omitnan");
[peak.correctedMaxAbsG, correctedRow] = max(CorrectedMaxAbsG, [], "omitnan");

if ~isempty(correctedRow) && isfinite(peak.correctedMaxAbsG)
    peak.selectedSource = "corrected";
    peak.maxAbsG = peak.correctedMaxAbsG;
    peak.signedPeakG = CorrectedSignedPeakG(correctedRow);
    peak.peakSensor = Sensor(correctedRow);
    peak.peakTimeSeconds = CorrectedPeakTimeSeconds(correctedRow);
elseif ~isempty(rawRow) && isfinite(peak.rawMaxAbsG)
    peak.selectedSource = "raw";
    peak.maxAbsG = peak.rawMaxAbsG;
    peak.signedPeakG = RawSignedPeakG(rawRow);
    peak.peakSensor = Sensor(rawRow);
    peak.peakTimeSeconds = RawPeakTimeSeconds(rawRow);
else
    peak.selectedSource = "";
    peak.maxAbsG = NaN;
    peak.signedPeakG = NaN;
    peak.peakSensor = NaN;
    peak.peakTimeSeconds = NaN;
end

end

function numSensors = inferNumberOfSensors(varNames)

tokens = regexp(varNames, "^S(\d+)_(?:a[xyz]|mag)_g", "tokens", "once");
sensorIds = [];

for iToken = 1:numel(tokens)
    if ~isempty(tokens{iToken})
        sensorIds(end + 1) = str2double(tokens{iToken}{1}); %#ok<AGROW>
    end
end

if isempty(sensorIds)
    error("Could not infer sensors from the table variable names.");
end

numSensors = max(sensorIds);

end

function t = selectTimeHistoryTime(T)

if ismember("t_arduino_elapsed_s", T.Properties.VariableNames)
    t = double(T.t_arduino_elapsed_s);
elseif ismember("t_matlab_elapsed_s", T.Properties.VariableNames)
    t = double(T.t_matlab_elapsed_s);
else
    t = nan(height(T), 1);
end

end

function [maxAbsG, signedPeakG, peakTimeSeconds] = findTimeHistoryPeak(values, t)

finiteIndices = find(isfinite(values));

if isempty(finiteIndices)
    maxAbsG = NaN;
    signedPeakG = NaN;
    peakTimeSeconds = NaN;
    return;
end

[maxAbsG, localIndex] = max(abs(values(finiteIndices)));
peakIndex = finiteIndices(localIndex);
signedPeakG = values(peakIndex);
peakTimeSeconds = t(peakIndex);

end
