function [time, acceleration, info] = ...
    ExtractHannoverChannelsPortoAlegre(T, varargin)
% ExtractHannoverChannelsPortoAlegre
%
% Adapts a Hannover sensor-rig table to the four physical acceleration
% channels expected by the Porto Alegre reference algorithm.

parser = inputParser;
parser.FunctionName = mfilename;
addParameter(parser, "StructuralSensors", [5, 4, 3, 2], ...
    @(x) isnumeric(x) && isvector(x) && numel(x) == 4 && ...
    all(isfinite(x)) && all(x >= 1) && all(mod(x, 1) == 0));
addParameter(parser, "Direction", "y", ...
    @(x) ischar(x) || isstring(x));
addParameter(parser, "UseCorrectedSignals", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "Gravity", 9.81, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
parse(parser, varargin{:});

if ~istable(T) || height(T) < 2
    error("T must be a nonempty Hannover sensor-rig table.");
end

structuralSensors = double(parser.Results.StructuralSensors(:).');
direction = lower(strtrim(string(parser.Results.Direction)));
useCorrectedSignals = logical(parser.Results.UseCorrectedSignals);
gravity = parser.Results.Gravity;

if ~ismember(direction, ["x", "y", "z"])
    error('Direction must be "x", "y", or "z".');
end

variableNames = string(T.Properties.VariableNames);
timeCandidates = [ ...
    "t_arduino_elapsed_s", ...
    "t_arduino_s", ...
    "t_matlab_elapsed_s"];
timeName = "";

for candidate = timeCandidates
    if ismember(candidate, variableNames)
        timeName = candidate;
        break;
    end
end

if strlength(timeName) == 0
    error("No supported Hannover time column was found.");
end

time = double(T.(timeName));
time = time - time(1);
accelerationG = nan(height(T), 4);
sourceColumns = strings(1, 4);

for iChannel = 1:4
    sensor = structuralSensors(iChannel);
    correctedName = sprintf( ...
        "S%d_a%s_g_corr", sensor, char(direction));
    rawName = sprintf("S%d_a%s_g", sensor, char(direction));

    if useCorrectedSignals && ismember(correctedName, variableNames)
        selectedName = string(correctedName);
    elseif ismember(rawName, variableNames)
        selectedName = string(rawName);
    else
        error("Required Hannover acceleration column is missing: %s", ...
            correctedName);
    end

    accelerationG(:, iChannel) = double(T.(selectedName));
    sourceColumns(iChannel) = selectedName;
end

acceleration = gravity * accelerationG;

info = struct();
info.timeColumn = timeName;
info.sourceColumns = sourceColumns;
info.structuralSensors = structuralSensors;
info.structuralChannelMeaning = [ ...
    "DoF 1 / top mass", ...
    "DoF 2", ...
    "DoF 3", ...
    "DoF 4 / bottom impacted mass"];
info.direction = direction;
info.useCorrectedSignals = useCorrectedSignals;
info.inputUnit = "g";
info.outputUnit = "m/s^2";
info.gravity = gravity;
info.excludedSensor = 1;
info.excludedSensorMeaning = "base/reference sensor";

end
