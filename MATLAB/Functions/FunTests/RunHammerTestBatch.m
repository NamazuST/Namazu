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
%       "FFTOptions", {"FMax", 90, "FrequencyResolutionHz", 0.1});

%% -------------------- SETTINGS --------------------
if nargin < 1 || isempty(N)
    N = 10;
end

parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, "Port", "COM5", @(x) ischar(x) || isstring(x));
addParameter(parser, "Baud", 1000000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "NumSensors", 5, @(x) isnumeric(x) && isscalar(x) && ...
    x > 0 && mod(x, 1) == 0);
addParameter(parser, "SampleRate", 250, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "DurationSeconds", 15, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "Direction", "y", @(x) ischar(x) || isstring(x));
addParameter(parser, "UseCorrectedData", false, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "CorrectionMeans", [], @(x) isempty(x) || isnumeric(x) || istable(x));
addParameter(parser, "AccelerometerRangeG", 8, @(x) isnumeric(x) && isscalar(x) && x > 0);

addParameter(parser, "OutputRoot", pwd, @(x) ischar(x) || isstring(x));
addParameter(parser, "FolderName", "", @(x) ischar(x) || isstring(x));
addParameter(parser, "FilePrefix", "hammer_test", @(x) ischar(x) || isstring(x));
addParameter(parser, "SaveSummary", true, @(x) islogical(x) || isnumeric(x));

addParameter(parser, "RunFFTAnalysis", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "FFTOptions", {"FMax", 90, "FrequencyResolutionHz", 0.1, ...
    "MinPeakDistanceHz", 10, "MakePlots", false}, @(x) iscell(x));

addParameter(parser, "PromptBeforeEachRun", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "CountdownSeconds", 0, @(x) isnumeric(x) && isscalar(x) && ...
    x >= 0 && mod(x, 1) == 0);
addParameter(parser, "MakeLivePlot", false, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "PlotWindowSeconds", 10, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "PlotUpdateRateHz", 30, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "ModeMatchToleranceHz", 3, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "MinModeOccurrenceFraction", 0.5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
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
correctionMeansInput = parser.Results.CorrectionMeans;
accelerometerRangeG = parser.Results.AccelerometerRangeG;

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
plotUpdateRateHz = parser.Results.PlotUpdateRateHz;
modeMatchToleranceHz = parser.Results.ModeMatchToleranceHz;
minModeOccurrenceFraction = parser.Results.MinModeOccurrenceFraction;
verbose = logical(parser.Results.Verbose);

[quantityIndex, quantityLabel] = parseQuantityOfInterest(direction);

if strlength(folderName) == 0
    todayText = char(datetime("now", "Format", "yyyy-MM-dd-HH-mm-ss"));
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

countdownAudio = loadCountdownAudio(functionFolder, countdownSeconds > 0);

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

if ~isempty(correctionMeansInput)
    validationMeans = normalizeCorrectionMeans(correctionMeansInput, NumSens);

    if verbose
        fprintf("Using externally supplied correction means for hammer-test runs.\n");
    end
elseif any(isnan(validationMeans(:, 1:3)), "all") && verbose
    warning("RunHammerTestBatch:MissingValidationMeans", ...
        "Some correction means are missing. Corrected channels may contain NaN.");
end

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
batch.accelerometerRangeG = accelerometerRangeG;
batch.correctionMeans = validationMeanTable;
batch.countdownAudio = countdownAudio.metadata;
batch.modeMatchToleranceHz = modeMatchToleranceHz;
batch.minModeOccurrenceFraction = minModeOccurrenceFraction;
batch.runFFTAnalysis = runFFTAnalysis;
batch.analysisDeferred = ~runFFTAnalysis;
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
        runCountdown(countdownSeconds, countdownAudio);
    end

    runStartedAt = datetime("now", "TimeZone", "local");

    [T, runMeta] = acquireOneHammerRun( ...
        s, ...
        NumSens, ...
        NumValsTotal, ...
        sampleRate, ...
        durationSeconds, ...
        validationMeans, ...
        accelerometerRangeG, ...
        quantityIndex, ...
        quantityLabel, ...
        direction, ...
        useCorrectedData, ...
        makeLivePlot, ...
        plotWindowSeconds, ...
        plotUpdateRateHz, ...
        countdownAudio);

    runMeta.runIndex = iRun;
    runMeta.runStartedAt = runStartedAt;
    runMeta.runCompletedAt = datetime("now", "TimeZone", "local");
    runMeta.outputFolder = string(outputFolder);

    fftResults = [];
    analysisError = "";

    if runFFTAnalysis && runMeta.quality.usableForAnalysis
        try
            fftResults = EstimateEigenfrequencyFFT(T, fftOptions{:});
            freqCells{iRun} = fftResults.freqHz;
            zetaCells{iRun} = fftResults.zeta;
        catch ME
            analysisError = string(ME.message);
            warning("FFT analysis failed for hammer test %d: %s", iRun, ME.message);
        end
    elseif runFFTAnalysis
        analysisError = "Run quality gate failed: " + ...
            strjoin(runMeta.quality.messages, "; ");
        warning("RunHammerTestBatch:QualityGateFailed", ...
            "Skipping FFT analysis for hammer test %d: %s", iRun, analysisError);
    end

    runMeta.analysisError = analysisError;

    if runMeta.clipping.hasClipping
        warning("RunHammerTestBatch:ClippingDetected", ...
            ["Hammer test %d reached the +/-%.1f g accelerometer range: " ...
            "maximum %.4f g on sensor %d, %s-axis (%d full-scale axis samples)."], ...
            iRun, accelerometerRangeG, runMeta.clipping.maxAbsG, ...
            runMeta.clipping.peakSensor, runMeta.clipping.peakAxis, ...
            runMeta.clipping.atLimitSampleCount);
    elseif runMeta.clipping.nearLimit
        warning("RunHammerTestBatch:NearClipping", ...
            ["Hammer test %d came within 95%% of the +/-%.1f g range: " ...
            "maximum %.4f g on sensor %d, %s-axis."], ...
            iRun, accelerometerRangeG, runMeta.clipping.maxAbsG, ...
            runMeta.clipping.peakSensor, runMeta.clipping.peakAxis);
    end

    if ~runMeta.quality.usableForAnalysis
        warning("RunHammerTestBatch:RunNotUsable", ...
            "Hammer test %d was saved but excluded from analysis: %s", ...
            iRun, strjoin(runMeta.quality.messages, "; "));
    end

    if ~isempty(runMeta.quality.warnings)
        warning("RunHammerTestBatch:RunQualityWarning", ...
            "Hammer test %d quality warning: %s", ...
            iRun, strjoin(runMeta.quality.warnings, "; "));
    end

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
    batch.run(iRun).hasClipping = runMeta.clipping.hasClipping;
    batch.run(iRun).nearClipping = runMeta.clipping.nearLimit;
    batch.run(iRun).maxAbsAccelerationG = runMeta.clipping.maxAbsG;
    batch.run(iRun).atLimitSampleCount = runMeta.clipping.atLimitSampleCount;
    batch.run(iRun).maxAbsTimeHistoryG = runMeta.timeHistoryPeak.maxAbsG;
    batch.run(iRun).signedPeakTimeHistoryG = runMeta.timeHistoryPeak.signedPeakG;
    batch.run(iRun).peakTimeHistorySensor = runMeta.timeHistoryPeak.peakSensor;
    batch.run(iRun).peakTimeHistorySeconds = runMeta.timeHistoryPeak.peakTimeSeconds;
    batch.run(iRun).peakTimeHistorySource = runMeta.timeHistoryPeak.selectedSource;
    batch.run(iRun).usableForAnalysis = runMeta.quality.usableForAnalysis;
    batch.run(iRun).qualityMessages = runMeta.quality.messages;
    batch.run(iRun).qualityWarnings = runMeta.quality.warnings;
    batch.run(iRun).estimatedMissingSamples = runMeta.quality.estimatedMissingSamples;
    batch.run(iRun).impactPeakG = runMeta.quality.impactPeakG;
    batch.run(iRun).impactPeakToNoiseRatio = runMeta.quality.impactPeakToNoiseRatio;
    batch.run(iRun).multipleImpactSuspected = runMeta.quality.multipleImpactSuspected;

    if ~isempty(fftResults)
        batch.run(iRun).freqHz = fftResults.freqHz;
        batch.run(iRun).zeta = fftResults.zeta;
    end

    fprintf("Saved hammer test %d to %s\n", iRun, filePath);
end

batch.completedAt = datetime("now", "TimeZone", "local");
[batch.freqMatrixHz, batch.zetaMatrix, batch.modeInfo] = ...
    MatchModalPeaksAcrossRuns(freqCells, zetaCells, ...
        "ToleranceHz", modeMatchToleranceHz, ...
        "MinOccurrenceFraction", minModeOccurrenceFraction);
batch.freqMeanHz = mean(batch.freqMatrixHz, 1, "omitnan");
batch.freqStdHz = std(batch.freqMatrixHz, 0, 1, "omitnan");
batch.zetaMean = mean(batch.zetaMatrix, 1, "omitnan");
batch.zetaStd = std(batch.zetaMatrix, 0, 1, "omitnan");

if saveSummary
    summaryFile = fullfile(outputFolder, "hammer_test_summary.mat");
    batch.summaryFile = string(summaryFile);
    save(summaryFile, "batch");
    fprintf("Saved hammer-test summary to %s\n", summaryFile);
end

end

%% ========================================================================
% LOCAL HELPER FUNCTIONS
% ========================================================================

function [T, meta] = acquireOneHammerRun(s, NumSens, NumValsTotal, sampleRate, ...
    durationSeconds, validationMeans, accelerometerRangeG, quantityIndex, quantityLabel, direction, ...
    useCorrectedData, makeLivePlot, plotWindowSeconds, plotUpdateRateHz, countdownAudio)

estimatedRows = ceil(durationSeconds * sampleRate * 1.5) + 200;
data = nan(estimatedRows, NumValsTotal);
t_matlab = NaT(estimatedRows, 1, "TimeZone", "local");

plotState = setupLivePlot(NumSens, quantityLabel, direction, makeLivePlot);
plotCleanup = onCleanup(@() closeFigureSafely(plotState.figure));

k = 0;
t0_arduino_ms = NaN;
currentValidationSensor = NaN;
plotEverySamples = max(1, round(sampleRate / plotUpdateRateHz));
lastPlottedSample = 0;

if makeLivePlot && isvalid(plotState.figure)
    plotState.axes.XLim = [0, max(durationSeconds, plotWindowSeconds)];
end

flush(s);
pause(0.05);
playSoundSafely(countdownAudio.startSignal, countdownAudio.sampleRate, "start");
fprintf("Recording now for %.2f s. Hit the structure once.\n", durationSeconds);
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

    shouldUpdatePlot = mod(k, plotEverySamples) == 0;

    if makeLivePlot && isvalid(plotState.figure) && shouldUpdatePlot
        plotIndices = (lastPlottedSample + 1):k;
        plotValues = data(plotIndices, :);
        elapsedMilliseconds = plotValues(:, 1) - t0_arduino_ms;
        elapsedMilliseconds(elapsedMilliseconds < 0) = ...
            elapsedMilliseconds(elapsedMilliseconds < 0) + 2^32 / 1000;
        tPlot = elapsedMilliseconds / 1000;

        for iSens = 1:NumSens
            yPlot = selectAccelerationValue( ...
                plotValues, iSens, quantityIndex, validationMeans, useCorrectedData);
            addpoints(plotState.lines(iSens), tPlot, yPlot);
        end

        lastPlottedSample = k;
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
T.t_arduino_elapsed_s = unwrapArduinoMilliseconds(T.t_arduino_ms);
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
meta.plotUpdateRateHz = plotUpdateRateHz;
meta.validationMeans = createValidationMeanTable(validationMeans, NumSens);
meta.accelerometerRangeG = accelerometerRangeG;
meta.actualSampleRateArduinoHz = estimateSampleRate(T.t_arduino_elapsed_s);
meta.actualSampleRateMatlabHz = estimateSampleRate(T.t_matlab_elapsed_s);
meta.clipping = detectAccelerationClipping(T, NumSens, accelerometerRangeG);
meta.timeHistoryPeak = SummarizeHammerTimeHistoryPeak(T, ...
    "NumSensors", NumSens, "Direction", direction);
meta.quality = AssessHammerRunQuality(T, ...
    "NumSensors", NumSens, ...
    "Direction", direction, ...
    "SampleRate", sampleRate, ...
    "DurationSeconds", durationSeconds, ...
    "Clipping", meta.clipping);

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
runSummary.hasClipping = false;
runSummary.nearClipping = false;
runSummary.maxAbsAccelerationG = NaN;
runSummary.atLimitSampleCount = NaN;
runSummary.maxAbsTimeHistoryG = NaN;
runSummary.signedPeakTimeHistoryG = NaN;
runSummary.peakTimeHistorySensor = NaN;
runSummary.peakTimeHistorySeconds = NaN;
runSummary.peakTimeHistorySource = "";
runSummary.usableForAnalysis = false;
runSummary.qualityMessages = strings(0, 1);
runSummary.qualityWarnings = strings(0, 1);
runSummary.estimatedMissingSamples = NaN;
runSummary.impactPeakG = NaN;
runSummary.impactPeakToNoiseRatio = NaN;
runSummary.multipleImpactSuspected = false;

end

function validationMeanTable = createValidationMeanTable(validationMeans, NumSens)

validationMeanTable = array2table(validationMeans, ...
    "VariableNames", {'mean_ax_g', 'mean_ay_g', 'mean_az_g', 'mean_mag_g'});

validationMeanTable.Sensor = (1:NumSens).';
validationMeanTable = movevars(validationMeanTable, "Sensor", "Before", 1);

end

function clipping = detectAccelerationClipping(T, NumSens, accelerometerRangeG)

axisLabels = ["x", "y", "z"];
nRows = NumSens * numel(axisLabels);
Sensor = nan(nRows, 1);
Axis = strings(nRows, 1);
MinG = nan(nRows, 1);
MaxG = nan(nRows, 1);
MaxAbsG = nan(nRows, 1);
NearLimitCount = zeros(nRows, 1);
AtLimitCount = zeros(nRows, 1);

nearLimitG = 0.95 * accelerometerRangeG;
atLimitG = accelerometerRangeG - 5e-4;
iRow = 0;

for iSens = 1:NumSens
    for iAxis = 1:numel(axisLabels)
        iRow = iRow + 1;
        Sensor(iRow) = iSens;
        Axis(iRow) = axisLabels(iAxis);

        varName = sprintf("S%d_a%s_g", iSens, axisLabels(iAxis));

        if ~ismember(varName, T.Properties.VariableNames)
            continue;
        end

        values = T.(varName);
        MinG(iRow) = min(values, [], "omitnan");
        MaxG(iRow) = max(values, [], "omitnan");
        MaxAbsG(iRow) = max(abs(values), [], "omitnan");
        NearLimitCount(iRow) = sum(abs(values) >= nearLimitG, "omitnan");
        AtLimitCount(iRow) = sum(abs(values) >= atLimitG, "omitnan");
    end
end

summary = table( ...
    Sensor, ...
    Axis, ...
    MinG, ...
    MaxG, ...
    MaxAbsG, ...
    NearLimitCount, ...
    AtLimitCount);

clipping = struct();
clipping.accelerometerRangeG = accelerometerRangeG;
clipping.nearLimitThresholdG = nearLimitG;
clipping.atLimitThresholdG = atLimitG;
clipping.summary = summary;
[clipping.maxAbsG, peakRow] = max(MaxAbsG, [], "omitnan");

if isempty(peakRow) || ~isfinite(clipping.maxAbsG)
    clipping.peakSensor = NaN;
    clipping.peakAxis = "";
    clipping.signedPeakG = NaN;
else
    clipping.peakSensor = Sensor(peakRow);
    clipping.peakAxis = Axis(peakRow);

    if abs(MinG(peakRow)) > abs(MaxG(peakRow))
        clipping.signedPeakG = MinG(peakRow);
    else
        clipping.signedPeakG = MaxG(peakRow);
    end
end

clipping.nearLimitSampleCount = sum(NearLimitCount);
clipping.atLimitSampleCount = sum(AtLimitCount);
clipping.nearLimit = clipping.nearLimitSampleCount > 0;
clipping.hasClipping = clipping.atLimitSampleCount > 0;

end

function validationMeans = normalizeCorrectionMeans(correctionMeansInput, NumSens)

if istable(correctionMeansInput)
    T = correctionMeansInput;

    if ismember("Sensor", string(T.Properties.VariableNames))
        T = sortrows(T, "Sensor");
    end

    namesLower = lower(string(T.Properties.VariableNames));
    desiredNames = ["mean_ax_g", "mean_ay_g", "mean_az_g", "mean_mag_g"];
    validationMeans = nan(height(T), 4);

    for iCol = 1:numel(desiredNames)
        idx = find(namesLower == desiredNames(iCol), 1);

        if ~isempty(idx)
            validationMeans(:, iCol) = T{:, idx};
        end
    end
else
    validationMeans = double(correctionMeansInput);
end

if size(validationMeans, 1) < NumSens || size(validationMeans, 2) < 3
    error("CorrectionMeans must contain at least %d rows and 3 columns.", NumSens);
end

validationMeans = validationMeans(1:NumSens, :);

if size(validationMeans, 2) == 3
    validationMeans(:, 4) = sqrt(sum(validationMeans(:, 1:3).^2, 2));
elseif size(validationMeans, 2) > 4
    validationMeans = validationMeans(:, 1:4);
end

if any(~isfinite(validationMeans(:, 1:3)), "all")
    error("CorrectionMeans contains non-finite axis offsets.");
end

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

function runCountdown(countdownSeconds, countdownAudio)

countdownSeconds = floor(countdownSeconds);

for i = countdownSeconds:-1:1
    fprintf("Starting in %d...\n", i);

    if i > 1
        playSoundSafely( ...
            countdownAudio.countdownSignal, countdownAudio.sampleRate, "countdown");
    end

    pause(1);
end

end

function countdownAudio = loadCountdownAudio(functionFolder, shouldLoad)

countdownAudio = struct();
countdownAudio.countdownSignal = [];
countdownAudio.startSignal = [];
countdownAudio.sampleRate = 44100;
countdownAudio.metadata = struct( ...
    "enabled", false, ...
    "countdownFile", "", ...
    "startFile", "", ...
    "countdownDurationSeconds", 0, ...
    "startDurationSeconds", 0);

if ~shouldLoad
    return;
end

if exist("mariostart_002.mp3", 'file')
countdownFile = fullfile(functionFolder, "mariostart_002.mp3");
startFile = fullfile(functionFolder, "mariostart_008.mp3");
end

try
    if exist("mariostart_002.mp3", 'file')
    [countdownSignal, fsCountdown] = audioread(countdownFile);
    [startSignal, fsStart] = audioread(startFile);
    else
        load gong.mat
        countdownSignal = y;
        fsCountdown = Fs;
        startSignal = y;
        fsStart = Fs;
    end
    if fsCountdown ~= fsStart
        error("Countdown audio files must use the same sample rate.");
    end

    countdownAudio.countdownSignal = countdownSignal;
    countdownAudio.startSignal = startSignal;
    countdownAudio.sampleRate = fsCountdown;
    countdownAudio.metadata.enabled = true;
    countdownAudio.metadata.countdownFile = string(countdownFile);
    countdownAudio.metadata.startFile = string(startFile);
    countdownAudio.metadata.countdownDurationSeconds = ...
        size(countdownSignal, 1) / fsCountdown;
    countdownAudio.metadata.startDurationSeconds = size(startSignal, 1) / fsStart;
catch ME
    warning("RunHammerTestBatch:CountdownAudioUnavailable", ...
        "Audio countdown is disabled: %s", ME.message);
end

end

function playSoundSafely(signal, sampleRate, cueName)

if isempty(signal)
    return;
end

try
    sound(signal, sampleRate);
catch ME
    warning("RunHammerTestBatch:AudioPlaybackFailed", ...
        "Could not play the %s cue; continuing silently: %s", cueName, ME.message);
end

end

function elapsedSeconds = unwrapArduinoMilliseconds(tMilliseconds)

tMilliseconds = double(tMilliseconds(:));
unwrappedMilliseconds = tMilliseconds;
wrapMilliseconds = 2^32 / 1000;
offsetMilliseconds = 0;

for i = 2:numel(tMilliseconds)
    if tMilliseconds(i) - tMilliseconds(i - 1) < -0.5 * wrapMilliseconds
        offsetMilliseconds = offsetMilliseconds + wrapMilliseconds;
    end

    unwrappedMilliseconds(i) = tMilliseconds(i) + offsetMilliseconds;
end

elapsedSeconds = (unwrappedMilliseconds - unwrappedMilliseconds(1)) / 1000;

end

function closeFigureSafely(fig)

if ~isempty(fig) && all(isgraphics(fig, "figure"))
    close(fig);
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
    y = vals(:, baseIndex + quantityIndex - 1);

    if useCorrectedData
        offset = validationMeans(iSens, quantityIndex);

        if isfinite(offset)
            y = y - offset;
        end
    end

else
    y = vals(:, baseIndex + 3);

    if useCorrectedData
        offsets = validationMeans(iSens, 1:3);

        if all(isfinite(offsets))
            corrected = [
                vals(:, baseIndex) - offsets(1), ...
                vals(:, baseIndex + 1) - offsets(2), ...
                vals(:, baseIndex + 2) - offsets(3)
            ];
            y = sqrt(sum(corrected.^2, 2));
        end
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

        if ismember(rawName, T.Properties.VariableNames) && isfinite(offset)
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
