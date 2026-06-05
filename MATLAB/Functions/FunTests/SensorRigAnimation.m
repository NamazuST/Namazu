[T, validationMeanTable, meta] = TestSensorRigAnimation("y", "COM9", 1, 60, ...
    "SampleRate", 250, ...
    "Baud", 1000000, ...
    "AnalysisOptions", {"FMax", 100, ...
                        "FrequencyResolutionHz", 0.1, ...
                        "WindowDurationSeconds", 20, ...
                        "MinPeakDistanceHz", 15});

fsActual = 1000 / median(diff(T.t_arduino_ms));
disp(fsActual)

EstimateEigenfrequencyFFT(T)

function [sensorRigData, validationMeanTable, meta] = TestSensorRigAnimation(quantityOfInterest, port, NumSens, durationSeconds, varargin)
% TestSensorRigAnimation
% Live test for the MPU6050 serial sensor rig.
%
% The function records the full acceleration stream from every sensor while
% animating one selected quantity of interest for all sensors.
%
% Expected Arduino line format:
%   t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g;S2_ax_g,...
%
% Usage:
%   TestSensorRigAnimation("x", "COM9", 5, 30);
%   T = TestSensorRigAnimation("x", "COM9", 5, 30);
%   [T, means] = TestSensorRigAnimation("z", "COM9", 5, 60, ...
%       "UseCorrectedData", true);
%   [T, means, meta] = TestSensorRigAnimation("y", "COM9", 5, 30, ...
%       "SaveData", true, "OutputFolder", "Measurements");
%   [T, means, meta] = TestSensorRigAnimation("y", "COM9", 5, 30, ...
%       "RunAnalysis", true);
%   [T, means, meta] = TestSensorRigAnimation("y", "COM9", 5, 60, ...
%       "AnalysisOptions", {"FMax", 100, "FrequencyResolutionHz", 0.25});
%
% SaveData defaults to true when the function is called without output
% arguments, and false when the output table is assigned.

if nargin < 1 || isempty(quantityOfInterest)
    quantityOfInterest = "x";
end

if nargin < 2 || isempty(port)
    port = "COM9";
end

if nargin < 3 || isempty(NumSens)
    NumSens = 5;
end

if nargin < 4 || isempty(durationSeconds)
    durationSeconds = 30;
end

parser = inputParser;
parser.FunctionName = mfilename;
addParameter(parser, "Baud", 1000000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "SampleRate", 250, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "PlotWindowSeconds", 10, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "UseCorrectedData", false, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "SaveData", [], @(x) isempty(x) || islogical(x) || isnumeric(x));
addParameter(parser, "OutputFolder", pwd, @(x) ischar(x) || isstring(x));
addParameter(parser, "Verbose", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "RunAnalysis", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "AnalysisDirection", [], @(x) isempty(x) || ischar(x) || isstring(x));
addParameter(parser, "AnalysisOptions", {"FMax", 100, "FrequencyResolutionHz", 0.25}, @(x) iscell(x));
parse(parser, varargin{:});

baud = parser.Results.Baud;
sampleRate = parser.Results.SampleRate;
plotWindowSeconds = parser.Results.PlotWindowSeconds;
useCorrectedData = logical(parser.Results.UseCorrectedData);

if isempty(parser.Results.SaveData)
    saveData = nargout == 0;
else
    saveData = logical(parser.Results.SaveData);
end

outputFolder = string(parser.Results.OutputFolder);
verbose = logical(parser.Results.Verbose);
runAnalysis = logical(parser.Results.RunAnalysis);
analysisDirection = parser.Results.AnalysisDirection;
analysisOptions = parser.Results.AnalysisOptions;

validateattributes(NumSens, {'numeric'}, {'scalar', 'integer', 'positive'}, mfilename, 'NumSens');
validateattributes(durationSeconds, {'numeric'}, {'scalar', 'positive'}, mfilename, 'durationSeconds');

[quantityIndex, quantityLabel, quantityUnitLabel] = parseQuantityOfInterest(quantityOfInterest);

NumValsPerSens = 4;                          % ax_g, ay_g, az_g, mag_g
NumValsTotal = 1 + NumSens*NumValsPerSens;   % +1 for t_ms

%% -------------------- CONNECT --------------------
port = string(port);
portList = serialportlist("available");

if ~any(strcmp(string(portList), port))
    error("Sensor port %s not found/open or port is in use. Check USB connection!", port);
end

fprintf("Opening sensor rig serial port %s at %d baud...\n", port, baud);

s = serialport(port, baud);
configureTerminator(s, "CR/LF");
s.Timeout = 5;

cleanupObj = onCleanup(@() cleanupSensorSerial(s));

flush(s);

% Give Arduino time to restart after opening the serial port.
pause(2);

%% -------------------- PLOT SETUP --------------------
plotFigure = figure("Name", sprintf("MPU6050 %s-axis live test", quantityLabel));
plotAxes = axes(plotFigure);
hold(plotAxes, "on");
grid(plotAxes, "on");
box(plotAxes, "on");

colors = lines(NumSens);
sensorLines = gobjects(NumSens, 1);

for iSens = 1:NumSens
    sensorLines(iSens) = animatedline(plotAxes, ...
        "Color", colors(iSens, :), ...
        "LineWidth", 1.2, ...
        "DisplayName", sprintf("Sensor %d", iSens));
end

xlabel(plotAxes, "Arduino elapsed time [s]");

if useCorrectedData
    ylabel(plotAxes, sprintf("Corrected %s [g]", quantityUnitLabel), "Interpreter", "none");
    title(plotAxes, sprintf("Corrected %s acceleration of all MPU6050 sensors", quantityLabel), "Interpreter", "none");
else
    ylabel(plotAxes, sprintf("Raw %s [g]", quantityUnitLabel), "Interpreter", "none");
    title(plotAxes, sprintf("Raw %s acceleration of all MPU6050 sensors", quantityLabel), "Interpreter", "none");
end

legend(plotAxes, "show", "Location", "best");

%% -------------------- WAIT FOR LIVE SENSOR STREAM --------------------
if verbose
    fprintf("Waiting for sensor rig stream...\n");
end

validationMeans = nan(NumSens, 4); % columns: mean ax, mean ay, mean az, mean |a|
currentValidationSensor = NaN;
firstVals = [];
firstMatlabTime = NaT(1, 1, "TimeZone", "local");

while isempty(firstVals)
    line = readline(s);
    currentMatlabTime = datetime("now", "TimeZone", "local");

    [isData, vals, validationMeans, currentValidationSensor] = ...
        parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, verbose);

    if isData && numel(vals) == NumValsTotal
        firstVals = vals;
        firstMatlabTime = currentMatlabTime;
    end
end

if verbose
    fprintf("Sensor rig stream detected. Recording %.2f s...\n", durationSeconds);
end

requiredValidationColumns = 1:min(quantityIndex, 3);
if useCorrectedData && any(isnan(validationMeans(:, requiredValidationColumns)), "all")
    warning("Some validation means are missing. Corrected live values for those sensors will be NaN.");
end

%% -------------------- ACQUIRE DATA --------------------
estimatedRows = ceil(durationSeconds * sampleRate * 1.3) + 100;
data = nan(estimatedRows, NumValsTotal);
t_matlab = NaT(estimatedRows, 1, "TimeZone", "local");

k = 0;
t0_arduino_ms = firstVals(1);
pendingVals = firstVals;
pendingMatlabTime = firstMatlabTime;
acquisitionTimer = tic;

while toc(acquisitionTimer) <= durationSeconds && isvalid(plotFigure)

    if ~isempty(pendingVals)
        vals = pendingVals;
        currentMatlabTime = pendingMatlabTime;
        pendingVals = [];
    else
        line = readline(s);
        currentMatlabTime = datetime("now", "TimeZone", "local");

        [isData, vals, validationMeans, currentValidationSensor] = ...
            parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, false);

        if ~isData || numel(vals) ~= NumValsTotal
            continue;
        end
    end

    k = k + 1;

    if k > size(data, 1)
        data = [data; nan(estimatedRows, NumValsTotal)]; %#ok<AGROW>
        t_matlab = [t_matlab; NaT(estimatedRows, 1, "TimeZone", "local")]; %#ok<AGROW>
    end

    data(k, :) = vals;
    t_matlab(k) = currentMatlabTime;

    tPlot = (vals(1) - t0_arduino_ms) / 1000;

    for iSens = 1:NumSens
        yPlot = selectAccelerationValue(vals, iSens, quantityIndex, validationMeans, useCorrectedData);
        addpoints(sensorLines(iSens), tPlot, yPlot);
    end

    plotAxes.XLim = [max(0, tPlot - plotWindowSeconds), max(plotWindowSeconds, tPlot)];
    drawnow limitrate
end

elapsedSeconds = toc(acquisitionTimer);

%% -------------------- CONVERT DATA TO TABLE --------------------
data = data(1:k, :);
t_matlab = t_matlab(1:k);

varNames = buildSensorRigVarNames(NumSens);
sensorRigData = array2table(data, "VariableNames", varNames);

if ~isempty(sensorRigData)
    sensorRigData.t_arduino_s = sensorRigData.t_arduino_ms / 1000;
    sensorRigData.t_arduino_elapsed_s = ...
        (sensorRigData.t_arduino_ms - sensorRigData.t_arduino_ms(1)) / 1000;

    sensorRigData.t_matlab = t_matlab;
    sensorRigData.t_matlab_elapsed_s = ...
        seconds(sensorRigData.t_matlab - sensorRigData.t_matlab(1));

    sensorRigData = movevars(sensorRigData, "t_arduino_s", "After", "t_arduino_ms");
    sensorRigData = movevars(sensorRigData, "t_arduino_elapsed_s", "After", "t_arduino_s");
    sensorRigData = movevars(sensorRigData, "t_matlab", "After", "t_arduino_elapsed_s");
    sensorRigData = movevars(sensorRigData, "t_matlab_elapsed_s", "After", "t_matlab");
end

validationMeanTable = array2table(validationMeans, ...
    "VariableNames", {'mean_ax_g', 'mean_ay_g', 'mean_az_g', 'mean_mag_g'});

validationMeanTable.Sensor = (1:NumSens).';
validationMeanTable = movevars(validationMeanTable, "Sensor", "Before", 1);

sensorRigData = addCorrectedAccelerationColumns(sensorRigData, validationMeans, NumSens);
sensorRigData.Properties.UserData.sampleRate = sampleRate;
sensorRigData.Properties.UserData.numberOfSensors = NumSens;
sensorRigData.Properties.UserData.baud = baud;
sensorRigData.Properties.UserData.port = port;

%% -------------------- METADATA AND OPTIONAL SAVE --------------------
meta = struct();
meta.port = port;
meta.baud = baud;
meta.numSensors = NumSens;
meta.sampleRate = sampleRate;
meta.durationSecondsRequested = durationSeconds;
meta.durationSecondsMeasured = elapsedSeconds;
meta.quantityOfInterest = string(quantityOfInterest);
meta.useCorrectedDataForPlot = useCorrectedData;
meta.outputFile = "";
meta.analysisResults = [];
meta.analysisError = "";
meta.analysisDirection = "";

if runAnalysis && ~isempty(sensorRigData) && height(sensorRigData) > 0

    if isempty(analysisDirection)
        analysisDirection = defaultAnalysisDirection(quantityIndex);
    end

    meta.analysisDirection = string(analysisDirection);

    try
        meta.analysisResults = EstimateEigenfrequencyFRF(sensorRigData, ...
            "Direction", analysisDirection, ...
            "SampleRate", sampleRate, ...
            "NumberOfSensors", NumSens, ...
            analysisOptions{:});
    catch ME
        meta.analysisError = string(ME.message);
        warningMessage = ['FRF analysis failed: ' ME.message];
        warning('%s', warningMessage);
    end
end

if saveData
    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    timestamp = char(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    meta.outputFile = fullfile(outputFolder, ...
        sprintf("sensorRig_%s_%s.mat", quantityLabel, timestamp));

    save(meta.outputFile, "sensorRigData", "validationMeanTable", "meta");
    fprintf("Saved sensor rig recording to %s\n", meta.outputFile);
end

if verbose
    fprintf("Recorded %d valid samples from %d sensors.\n", height(sensorRigData), NumSens);
end

end

function analysisDirection = defaultAnalysisDirection(quantityIndex)

directions = ["x", "y", "z", "y"];
analysisDirection = directions(quantityIndex);

end

%% ========================================================================
% LOCAL HELPER FUNCTIONS
% ========================================================================

function [quantityIndex, quantityLabel, quantityUnitLabel] = parseQuantityOfInterest(quantityOfInterest)

q = lower(strtrim(string(quantityOfInterest)));
q = replace(q, "-", "");
q = replace(q, "_", "");
q = replace(q, " ", "");

switch q
    case {"x", "ax", "axg"}
        quantityIndex = 1;
        quantityLabel = "x-axis";
        quantityUnitLabel = "x-acceleration";
    case {"y", "ay", "ayg"}
        quantityIndex = 2;
        quantityLabel = "y-axis";
        quantityUnitLabel = "y-acceleration";
    case {"z", "az", "azg"}
        quantityIndex = 3;
        quantityLabel = "z-axis";
        quantityUnitLabel = "z-acceleration";
    case {"mag", "magnitude", "norm"}
        quantityIndex = 4;
        quantityLabel = "magnitude";
        quantityUnitLabel = "acceleration magnitude";
    otherwise
        error('quantityOfInterest must be "x", "y", "z", or "mag".');
end

end

function y = selectAccelerationValue(vals, iSens, quantityIndex, validationMeans, useCorrectedData)

baseIndex = 2 + (iSens - 1)*4;

if quantityIndex <= 3
    y = vals(baseIndex + quantityIndex - 1);

    if useCorrectedData
        offset = validationMeans(iSens, quantityIndex);

        if isnan(offset)
            y = NaN;
        else
            y = y - offset;
        end
    end

else
    if useCorrectedData
        offsets = validationMeans(iSens, 1:3);

        if any(isnan(offsets))
            y = NaN;
        else
            corrected = [
                vals(baseIndex) - offsets(1), ...
                vals(baseIndex + 1) - offsets(2), ...
                vals(baseIndex + 2) - offsets(3)
            ];
            y = sqrt(sum(corrected.^2));
        end
    else
        y = vals(baseIndex + 3);
    end
end

end

function [isData, vals, validationMeans, currentValidationSensor] = ...
    parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, verbose)

isData = false;
vals = [];

line = strtrim(string(line));
lineChar = char(line);

if strlength(line) == 0
    return;
end

sensorToken = regexp(lineChar, '^Sensor\s+(\d+):$', 'tokens', 'once');

if ~isempty(sensorToken)
    currentValidationSensor = str2double(sensorToken{1});

    if verbose
        disp("Skipping non-data line: " + line);
    end

    return;
end

numPattern = '([+-]?(?:\d+\.?\d*|\.\d+)(?:[Ee][+-]?\d+)?)';

if ~isnan(currentValidationSensor) && ...
        currentValidationSensor >= 1 && currentValidationSensor <= NumSens

    token = regexp(lineChar, ['^Mean ax \[g\]:\s*' numPattern], 'tokens', 'once');
    if ~isempty(token)
        validationMeans(currentValidationSensor, 1) = str2double(token{1});
        if verbose; disp("Skipping non-data line: " + line); end
        return;
    end

    token = regexp(lineChar, ['^Mean ay \[g\]:\s*' numPattern], 'tokens', 'once');
    if ~isempty(token)
        validationMeans(currentValidationSensor, 2) = str2double(token{1});
        if verbose; disp("Skipping non-data line: " + line); end
        return;
    end

    token = regexp(lineChar, ['^Mean az \[g\]:\s*' numPattern], 'tokens', 'once');
    if ~isempty(token)
        validationMeans(currentValidationSensor, 3) = str2double(token{1});
        if verbose; disp("Skipping non-data line: " + line); end
        return;
    end

    token = regexp(lineChar, ['^Mean \|a\| \[g\]:\s*' numPattern], 'tokens', 'once');
    if ~isempty(token)
        validationMeans(currentValidationSensor, 4) = str2double(token{1});
        if verbose; disp("Skipping non-data line: " + line); end
        return;
    end
end

line2 = replace(line, ";", ",");
tokens = split(line2, ",");
valsTemp = str2double(tokens).';
NumValsTotal = 1 + NumSens*4;

if numel(valsTemp) == NumValsTotal && ~isnan(valsTemp(1))
    vals = valsTemp;
    isData = true;
elseif verbose
    disp("Skipping non-data line: " + line);
end

end

function varNames = buildSensorRigVarNames(NumSens)

baseNames = ["ax_g", "ay_g", "az_g", "mag_g"];
varNames = "t_arduino_ms";

for iSens = 1:NumSens
    sensorNames = strcat("S", string(iSens), "_", baseNames);
    varNames = [varNames, sensorNames]; %#ok<AGROW>
end

varNames = cellstr(varNames);

end

function T = addCorrectedAccelerationColumns(T, validationMeans, NumSens)

if isempty(T)
    return;
end

axisNames = ["ax_g", "ay_g", "az_g"];

for iSens = 1:NumSens
    for jAxis = 1:numel(axisNames)
        rawName = sprintf("S%d_%s", iSens, axisNames(jAxis));
        corrName = sprintf("S%d_%s_corr", iSens, axisNames(jAxis));

        offset = validationMeans(iSens, jAxis);

        if ismember(rawName, T.Properties.VariableNames) && ~isnan(offset)
            T.(corrName) = T.(rawName) - offset;
        else
            T.(corrName) = nan(height(T), 1);
        end
    end

    corrAx = sprintf("S%d_ax_g_corr", iSens);
    corrAy = sprintf("S%d_ay_g_corr", iSens);
    corrAz = sprintf("S%d_az_g_corr", iSens);
    corrMag = sprintf("S%d_mag_g_corr", iSens);

    T.(corrMag) = sqrt(T.(corrAx).^2 + T.(corrAy).^2 + T.(corrAz).^2);
end

end

function cleanupSensorSerial(s)

try
    flush(s);
catch
end

end
