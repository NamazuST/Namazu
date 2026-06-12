function batch = RunHammerTestBatch(N, varargin)
% RunHammerTestBatch
%
% Repeated hammer-test acquisition for the MPU6050 sensor rig. The function
% opens the sensor serial stream once, records N hammer impacts in a row,
% and stores each measurement in a separate MAT-file.
%
% Usage:
%   batch = RunHammerTestBatch(10);
%   batch = RunHammerTestBatch(20, "DurationSeconds", 12, "Direction", "y");
%   batch = RunHammerTestBatch(10, ...
%       "OutputRoot", "Measurements", ...
%       "FFTOptions", {"FMax", 100, "FrequencyResolutionHz", 0.1});

%% -------------------- SETTINGS --------------------
if nargin < 1 || isempty(N)
    N = 10;
end

parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, "Port", "COM9", @(x) ischar(x) || isstring(x));
addParameter(parser, "Baud", 1000000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "NumSensors", 5, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "SampleRate", 250, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "DurationSeconds", 12, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "Direction", "y", @(x) ischar(x) || isstring(x));
addParameter(parser, "UseCorrectedData", false, @(x) islogical(x) || isnumeric(x));

addParameter(parser, "OutputRoot", pwd, @(x) ischar(x) || isstring(x));
addParameter(parser, "FolderName", "", @(x) ischar(x) || isstring(x));
addParameter(parser, "FilePrefix", "hammer_test", @(x) ischar(x) || isstring(x));
addParameter(parser, "SaveSummary", true, @(x) islogical(x) || isnumeric(x));

addParameter(parser, "RunFFTAnalysis", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "FFTOptions", {"FMax", 100, "FrequencyResolutionHz", 0.1, ...
    "MinPeakDistanceHz", 15, "MakePlots", false}, @(x) iscell(x));

addParameter(parser, "PromptBeforeEachRun", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "CountdownSeconds", 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "MakeLivePlot", false, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "PlotWindowSeconds", 10, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "Verbose", true, @(x) islogical(x) || isnumeric(x));

parse(parser, varargin{:});

validateattributes(N, {'numeric'}, {'scalar', 'integer', 'positive'}, mfilename, 'N');

port = string(parser.Results.Port);
baud = parser.Results.Baud;
NumSens = double(parser.Results.NumSensors);
sampleRate = parser.Results.SampleRate;
durationSeconds = parser.Results.DurationSeconds;
direction = lower(strtrim(string(parser.Results.Direction)));
useCorrectedData = logical(parser.Results.UseCorrectedData);

outputRoot = string(parser.Results.OutputRoot);
folderName = string(parser.Results.FolderName);
filePrefix = string(parser.Results.FilePrefix);
saveSummary = logical(parser.Results.SaveSummary);

runFFTAnalysis = logical(parser.Results.RunFFTAnalysis);
fftOptions = parser.Results.FFTOptions;

promptBeforeEachRun = logical(parser.Results.PromptBeforeEachRun);
countdownSeconds = parser.Results.CountdownSeconds;
makeLivePlot = logical(parser.Results.MakeLivePlot);
plotWindowSeconds = parser.Results.PlotWindowSeconds;
verbose = logical(parser.Results.Verbose);

[quantityIndex, quantityLabel] = parseQuantityOfInterest(direction);

if strlength(folderName) == 0
    todayText = char(datetime("now", "Format", "yyyy-MM-dd-mm-ss"));
    folderName = string(todayText)+"-hammer-test";
end

outputFolder = fullfile(outputRoot, folderName);

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

functionFolder = fileparts(mfilename("fullpath"));
functionsRoot = fileparts(functionFolder);
postProcessingFolder = fullfile(functionsRoot, "PostProcessing");

if isfolder(postProcessingFolder)
    addpath(postProcessingFolder);
end

if runFFTAnalysis
    fftOptions = ensureNameValueOption(fftOptions, "Direction", defaultAnalysisDirection(quantityIndex));
    fftOptions = ensureNameValueOption(fftOptions, "SampleRate", sampleRate);
    fftOptions = ensureNameValueOption(fftOptions, "Sensors", 1:NumSens);
end

%% -------------------- CONNECT --------------------
portList = serialportlist("available");

if ~any(strcmp(string(portList), port))
    error("Sensor port %s not found/open or port is in use. Check USB connection.", port);
end

fprintf("Opening sensor rig serial port %s at %d baud...\n", port, baud);

s = serialport(port, baud);
configureTerminator(s, "CR/LF");
s.Timeout = 5;

cleanupObj = onCleanup(@() cleanupSensorSerial(s));

flush(s);
pause(2);

%% -------------------- WAIT FOR STREAM AND VALIDATION --------------------
NumValsPerSens = 4;
NumValsTotal = 1 + NumSens*NumValsPerSens;
validationMeans = nan(NumSens, 4);
currentValidationSensor = NaN;
firstValidSeen = false;

if verbose
    fprintf("Waiting for sensor rig live stream...\n");
end

while ~firstValidSeen
    line = readline(s);
    [isData, vals, validationMeans, currentValidationSensor] = ...
        parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, verbose);

    if isData && numel(vals) == NumValsTotal
        firstValidSeen = true;
    end
end

if verbose
    fprintf("Sensor rig stream detected.\n");
    fprintf("Output folder: %s\n", outputFolder);
end

flush(s);

validationMeanTable = createValidationMeanTable(validationMeans, NumSens);

%% -------------------- BATCH LOOP --------------------
batch = struct();
batch.outputFolder = string(outputFolder);
batch.startedAt = datetime("now", "TimeZone", "local");
batch.N = N;
batch.port = port;
batch.baud = baud;
batch.numSensors = NumSens;
batch.sampleRate = sampleRate;
batch.durationSeconds = durationSeconds;
batch.direction = direction;
batch.files = strings(N, 1);
batch.run = repmat(createEmptyRunSummary(), N, 1);

freqCells = cell(N, 1);
zetaCells = cell(N, 1);

for iRun = 1:N

    fprintf("\nHammer test %d/%d\n", iRun, N);

    if promptBeforeEachRun
        input("Press Enter to start recording, then hit with the hammer during the recording window.", "s");
    end

    if countdownSeconds > 0
        runCountdown(countdownSeconds);
    end

    flush(s);
    pause(0.05);

    runStartedAt = datetime("now", "TimeZone", "local");
    fprintf("Recording hammer test %d for %.2f s...\n", iRun, durationSeconds);

    [T, runMeta] = acquireOneHammerRun( ...
        s, ...
        NumSens, ...
        NumValsTotal, ...
        sampleRate, ...
        durationSeconds, ...
        validationMeans, ...
        quantityIndex, ...
        quantityLabel, ...
        direction, ...
        useCorrectedData, ...
        makeLivePlot, ...
        plotWindowSeconds);

    runMeta.runIndex = iRun;
    runMeta.runStartedAt = runStartedAt;
    runMeta.runCompletedAt = datetime("now", "TimeZone", "local");
    runMeta.outputFolder = string(outputFolder);

    fftResults = [];
    analysisError = "";

    if runFFTAnalysis
        try
            fftResults = EstimateEigenfrequencyFFT(T, fftOptions{:});
            freqCells{iRun} = fftResults.freqHz;
            zetaCells{iRun} = fftResults.zeta;
        catch ME
            analysisError = string(ME.message);
            warning("FFT analysis failed for hammer test %d: %s", iRun, ME.message);
        end
    end

    runMeta.analysisError = analysisError;

    fileName = sprintf("%s_%03d.mat", filePrefix, iRun);
    filePath = fullfile(outputFolder, fileName);

    sensorRigData = T;
    meta = runMeta;
    save(filePath, "T", "sensorRigData", "validationMeanTable", "meta", "fftResults");

    batch.files(iRun) = string(filePath);
    batch.run(iRun).index = iRun;
    batch.run(iRun).file = string(filePath);
    batch.run(iRun).numSamples = height(T);
    batch.run(iRun).actualSampleRateArduinoHz = runMeta.actualSampleRateArduinoHz;
    batch.run(iRun).actualSampleRateMatlabHz = runMeta.actualSampleRateMatlabHz;
    batch.run(iRun).analysisError = analysisError;

    if ~isempty(fftResults)
        batch.run(iRun).freqHz = fftResults.freqHz;
        batch.run(iRun).zeta = fftResults.zeta;
    end

    fprintf("Saved hammer test %d to %s\n", iRun, filePath);
end

batch.completedAt = datetime("now", "TimeZone", "local");
batch.freqMatrixHz = padNumericRows(freqCells);
batch.zetaMatrix = padNumericRows(zetaCells);
batch.freqMeanHz = mean(batch.freqMatrixHz, 1, "omitnan");
batch.freqStdHz = std(batch.freqMatrixHz, 0, 1, "omitnan");
batch.zetaMean = mean(batch.zetaMatrix, 1, "omitnan");
batch.zetaStd = std(batch.zetaMatrix, 0, 1, "omitnan");

if saveSummary
    summaryFile = fullfile(outputFolder, "hammer_test_summary.mat");
    save(summaryFile, "batch");
    batch.summaryFile = string(summaryFile);
    fprintf("Saved hammer-test summary to %s\n", summaryFile);
end

end

%% ========================================================================
% LOCAL HELPER FUNCTIONS
% ========================================================================

function [T, meta] = acquireOneHammerRun(s, NumSens, NumValsTotal, sampleRate, ...
    durationSeconds, validationMeans, quantityIndex, quantityLabel, direction, ...
    useCorrectedData, makeLivePlot, plotWindowSeconds)

estimatedRows = ceil(durationSeconds * sampleRate * 1.5) + 200;
data = nan(estimatedRows, NumValsTotal);
t_matlab = NaT(estimatedRows, 1, "TimeZone", "local");

plotState = setupLivePlot(NumSens, quantityLabel, direction, makeLivePlot);

k = 0;
t0_arduino_ms = NaN;
currentValidationSensor = NaN;
timerObj = tic;

while toc(timerObj) <= durationSeconds
    line = readline(s);
    currentMatlabTime = datetime("now", "TimeZone", "local");

    [isData, vals, validationMeans, currentValidationSensor] = ...
        parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, false);

    if ~isData || numel(vals) ~= NumValsTotal
        continue;
    end

    k = k + 1;

    if k > size(data, 1)
        data = [data; nan(estimatedRows, NumValsTotal)]; %#ok<AGROW>
        t_matlab = [t_matlab; NaT(estimatedRows, 1, "TimeZone", "local")]; %#ok<AGROW>
    end

    data(k, :) = vals;
    t_matlab(k) = currentMatlabTime;

    if isnan(t0_arduino_ms)
        t0_arduino_ms = vals(1);
    end

    if makeLivePlot && isvalid(plotState.figure)
        tPlot = (vals(1) - t0_arduino_ms) / 1000;

        for iSens = 1:NumSens
            yPlot = selectAccelerationValue(vals, iSens, quantityIndex, validationMeans, useCorrectedData);
            addpoints(plotState.lines(iSens), tPlot, yPlot);
        end

        plotState.axes.XLim = [max(0, tPlot - plotWindowSeconds), max(plotWindowSeconds, tPlot)];
        drawnow limitrate
    end
end

elapsedSeconds = toc(timerObj);

if k == 0
    error("No valid sensor samples were recorded.");
end

data = data(1:k, :);
t_matlab = t_matlab(1:k);

varNames = buildSensorRigVarNames(NumSens);
T = array2table(data, "VariableNames", varNames);

T.t_arduino_s = T.t_arduino_ms / 1000;
T.t_arduino_elapsed_s = (T.t_arduino_ms - T.t_arduino_ms(1)) / 1000;
T.t_matlab = t_matlab;
T.t_matlab_elapsed_s = seconds(T.t_matlab - T.t_matlab(1));

T = movevars(T, "t_arduino_s", "After", "t_arduino_ms");
T = movevars(T, "t_arduino_elapsed_s", "After", "t_arduino_s");
T = movevars(T, "t_matlab", "After", "t_arduino_elapsed_s");
T = movevars(T, "t_matlab_elapsed_s", "After", "t_matlab");

T = addCorrectedAccelerationColumns(T, validationMeans, NumSens);
T.Properties.UserData.sampleRate = sampleRate;
T.Properties.UserData.numberOfSensors = NumSens;
T.Properties.UserData.testType = "hammer";

meta = struct();
meta.sampleRate = sampleRate;
meta.numSensors = NumSens;
meta.durationSecondsRequested = durationSeconds;
meta.durationSecondsMeasured = elapsedSeconds;
meta.quantityOfInterest = direction;
meta.useCorrectedDataForPlot = useCorrectedData;
meta.validationMeans = createValidationMeanTable(validationMeans, NumSens);
meta.actualSampleRateArduinoHz = estimateSampleRate(T.t_arduino_elapsed_s);
meta.actualSampleRateMatlabHz = estimateSampleRate(T.t_matlab_elapsed_s);

end

function plotState = setupLivePlot(NumSens, quantityLabel, direction, makeLivePlot)

plotState = struct();
plotState.figure = gobjects(0);
plotState.axes = gobjects(0);
plotState.lines = gobjects(NumSens, 1);

if ~makeLivePlot
    return;
end

plotState.figure = figure("Name", sprintf("Hammer test live %s", quantityLabel));
plotState.axes = axes(plotState.figure);
hold(plotState.axes, "on");
grid(plotState.axes, "on");
box(plotState.axes, "on");

colors = lines(NumSens);

for iSens = 1:NumSens
    plotState.lines(iSens) = animatedline(plotState.axes, ...
        "Color", colors(iSens, :), ...
        "LineWidth", 1.2, ...
        "DisplayName", sprintf("Sensor %d", iSens));
end

xlabel(plotState.axes, "Arduino elapsed time [s]");
ylabel(plotState.axes, sprintf("%s acceleration [g]", direction), "Interpreter", "none");
title(plotState.axes, sprintf("Hammer test %s acceleration", quantityLabel), "Interpreter", "none");
legend(plotState.axes, "show", "Location", "best");

end

function runSummary = createEmptyRunSummary()

runSummary = struct();
runSummary.index = NaN;
runSummary.file = "";
runSummary.numSamples = NaN;
runSummary.actualSampleRateArduinoHz = NaN;
runSummary.actualSampleRateMatlabHz = NaN;
runSummary.analysisError = "";
runSummary.freqHz = [];
runSummary.zeta = [];

end

function validationMeanTable = createValidationMeanTable(validationMeans, NumSens)

validationMeanTable = array2table(validationMeans, ...
    "VariableNames", {'mean_ax_g', 'mean_ay_g', 'mean_az_g', 'mean_mag_g'});

validationMeanTable.Sensor = (1:NumSens).';
validationMeanTable = movevars(validationMeanTable, "Sensor", "Before", 1);

end

function fs = estimateSampleRate(t)

t = double(t(:));
t = t(isfinite(t));

if numel(t) < 2
    fs = NaN;
    return;
end

dt = median(diff(t));

if dt <= 0 || ~isfinite(dt)
    fs = NaN;
else
    fs = 1 / dt;
end

end

function value = padNumericRows(values)

maxLen = 0;

for i = 1:numel(values)
    maxLen = max(maxLen, numel(values{i}));
end

if maxLen == 0
    value = nan(numel(values), 0);
    return;
end

value = nan(numel(values), maxLen);

for i = 1:numel(values)
    row = values{i};
    value(i, 1:numel(row)) = row;
end

end

function runCountdown(countdownSeconds)

for i = countdownSeconds:-1:1
    fprintf("Starting in %d...\n", i);
    pause(1);
end

end

function options = ensureNameValueOption(options, name, value)

if hasNameValueOption(options, name)
    return;
end

options = [options, {name, value}];

end

function tf = hasNameValueOption(options, name)

tf = false;
name = string(name);

for i = 1:2:numel(options)
    if string(options{i}) == name
        tf = true;
        return;
    end
end

end

function [quantityIndex, quantityLabel] = parseQuantityOfInterest(quantityOfInterest)

q = lower(strtrim(string(quantityOfInterest)));
q = replace(q, "-", "");
q = replace(q, "_", "");
q = replace(q, " ", "");

switch q
    case {"x", "ax", "axg"}
        quantityIndex = 1;
        quantityLabel = "x-axis";
    case {"y", "ay", "ayg"}
        quantityIndex = 2;
        quantityLabel = "y-axis";
    case {"z", "az", "azg"}
        quantityIndex = 3;
        quantityLabel = "z-axis";
    case {"mag", "magnitude", "norm"}
        quantityIndex = 4;
        quantityLabel = "magnitude";
    otherwise
        error('Direction must be "x", "y", "z", or "mag".');
end

end

function analysisDirection = defaultAnalysisDirection(quantityIndex)

directions = ["x", "y", "z", "y"];
analysisDirection = directions(quantityIndex);

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
