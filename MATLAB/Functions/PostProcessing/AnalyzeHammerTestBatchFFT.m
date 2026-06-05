function summary = AnalyzeHammerTestBatchFFT(batchFolder, varargin)
% AnalyzeHammerTestBatchFFT
%
% Loads a folder created by RunHammerTestBatch, runs FFT envelope peak
% picking for every hammer-test MAT-file, and collects the frequencies and
% damping estimates in one summary structure and result files.
%
% Usage:
%   summary = AnalyzeHammerTestBatchFFT("Hammer test 2026-06-05");
%   summary = AnalyzeHammerTestBatchFFT("Hammer test 2026-06-05", ...
%       "FFTOptions", {"Direction", "y", "FMax", 100});
%   summary = AnalyzeHammerTestBatchFFT("Hammer test 2026-06-05", ...
%       "MeasurementsFileName", "measurements.txt", "NumMeasurementModes", 4);
%
% Each measurement file is expected to contain T or sensorRigData. If meta
% exists, it is passed to EstimateEigenfrequencyFFT for sample-rate metadata.

if nargin < 1 || isempty(batchFolder)
    todayText = char(datetime("today", "Format", "yyyy-MM-dd"));
    batchFolder = "Hammer test " + string(todayText);
end

parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, "FilePattern", "hammer_test_*.mat", @(x) ischar(x) || isstring(x));
addParameter(parser, "FileRegex", "^hammer_test_\d+\.mat$", @(x) ischar(x) || isstring(x));
addParameter(parser, "FFTOptions", {"FMax", 100, "FrequencyResolutionHz", 0.1, ...
    "MinPeakDistanceHz", 15, "MakePlots", false}, @(x) iscell(x));
addParameter(parser, "AutoLimitFMax", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "FMaxSafetyFactor", 0.98, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(parser, "SaveResultsToFiles", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "SaveSummary", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "SummaryFileName", "hammer_test_fft_summary.mat", @(x) ischar(x) || isstring(x));
addParameter(parser, "SaveTotalResults", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "ResultsFileName", "hammer_test_fft_results.csv", @(x) ischar(x) || isstring(x));
addParameter(parser, "ResultsTextFileName", "results.txt", @(x) ischar(x) || isstring(x));
addParameter(parser, "SaveMeasurementsFile", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "MeasurementsFileName", "measurements.txt", @(x) ischar(x) || isstring(x));
addParameter(parser, "NumMeasurementModes", 4, @(x) isnumeric(x) && isscalar(x) && ...
    x > 0 && mod(x, 1) == 0);
addParameter(parser, "Verbose", true, @(x) islogical(x) || isnumeric(x));

parse(parser, varargin{:});

batchFolder = string(batchFolder);
filePattern = string(parser.Results.FilePattern);
fileRegex = string(parser.Results.FileRegex);
fftOptions = parser.Results.FFTOptions;
autoLimitFMax = logical(parser.Results.AutoLimitFMax);
fMaxSafetyFactor = parser.Results.FMaxSafetyFactor;
saveResultsToFiles = logical(parser.Results.SaveResultsToFiles);
saveSummary = logical(parser.Results.SaveSummary);
summaryFileName = string(parser.Results.SummaryFileName);
saveTotalResults = logical(parser.Results.SaveTotalResults);
resultsFileName = string(parser.Results.ResultsFileName);
resultsTextFileName = string(parser.Results.ResultsTextFileName);
saveMeasurementsFile = logical(parser.Results.SaveMeasurementsFile);
measurementsFileName = string(parser.Results.MeasurementsFileName);
numMeasurementModes = parser.Results.NumMeasurementModes;
verbose = logical(parser.Results.Verbose);

if ~isfolder(batchFolder)
    error("Hammer-test folder does not exist: %s", batchFolder);
end

files = dir(fullfile(batchFolder, filePattern));
files = files(~[files.isdir]);
files = sortFileStructByName(files);

if strlength(fileRegex) > 0
    keep = false(numel(files), 1);

    for iFile = 1:numel(files)
        keep(iFile) = ~isempty(regexp(files(iFile).name, fileRegex, "once"));
    end

    files = files(keep);
end

if isempty(files)
    error("No measurement files matching %s and regex %s found in %s.", ...
        filePattern, fileRegex, batchFolder);
end

functionFolder = fileparts(mfilename("fullpath"));
addpath(functionFolder);

N = numel(files);
freqCells = cell(N, 1);
zetaCells = cell(N, 1);
run = repmat(createEmptyRunSummary(), N, 1);

for iRun = 1:N
    filePath = fullfile(files(iRun).folder, files(iRun).name);

    if verbose
        fprintf("Analyzing hammer-test file %d/%d: %s\n", iRun, N, files(iRun).name);
    end

    S = load(filePath);

    if isfield(S, "T")
        T = S.T;
    elseif isfield(S, "sensorRigData")
        T = S.sensorRigData;
    else
        error("File %s does not contain T or sensorRigData.", filePath);
    end

    if ~istable(T)
        error("Measurement data in %s is not a table.", filePath);
    end

    if isfield(S, "meta") && isstruct(S.meta)
        meta = S.meta;
    else
        meta = struct();
    end

    fftOptionsRun = fftOptions;
    [fsEstimate, fNyquistEstimate] = estimateSamplingInfo(T, meta, fftOptionsRun);
    [fMaxRequested, hasFMax] = getNameValueOption(fftOptionsRun, "FMax", 100);
    [fMinRequested, ~] = getNameValueOption(fftOptionsRun, "FMin", 0.5);
    fMaxUsed = fMaxRequested;
    autoLimitedFMax = false;

    if autoLimitFMax && isfinite(fNyquistEstimate) && isnumeric(fMaxRequested) && ...
            isscalar(fMaxRequested)
        fMaxLimit = fMaxSafetyFactor * fNyquistEstimate;

        if fMaxRequested > fMaxLimit
            fMaxUsed = fMaxLimit;
            fftOptionsRun = setNameValueOption(fftOptionsRun, "FMax", fMaxUsed);
            autoLimitedFMax = true;

            if verbose
                fprintf("  Limiting FMax from %.2f Hz to %.2f Hz; measured Nyquist is %.2f Hz.\n", ...
                    fMaxRequested, fMaxUsed, fNyquistEstimate);
            end
        elseif ~hasFMax
            fftOptionsRun = setNameValueOption(fftOptionsRun, "FMax", fMaxUsed);
        end
    end

    if isfinite(fMaxUsed) && isfinite(fMinRequested) && fMaxUsed <= fMinRequested
        warning("Usable FMax %.2f Hz is not above FMin %.2f Hz for %s.", ...
            fMaxUsed, fMinRequested, files(iRun).name);
    end

    if ~hasNameValueOption(fftOptionsRun, "Meta") && ~isempty(fieldnames(meta))
        nOptions = numel(fftOptionsRun);
        fftOptionsRun(nOptions + 1:nOptions + 2) = {"Meta", meta};
    end

    try
        fftResults = EstimateEigenfrequencyFFT(T, fftOptionsRun{:});
        analysisError = "";
        freqCells{iRun} = fftResults.freqHz;
        zetaCells{iRun} = fftResults.zeta;
    catch ME
        fftResults = [];
        analysisError = string(ME.message);
        warning("FFT analysis failed for %s: %s", files(iRun).name, ME.message);
    end

    meta.fftAnalysisUpdatedAt = datetime("now", "TimeZone", "local");
    meta.fftAnalysisError = analysisError;

    if saveResultsToFiles
        save(filePath, "fftResults", "meta", "-append");
    end

    run(iRun).index = iRun;
    run(iRun).file = string(filePath);
    run(iRun).numSamples = height(T);
    run(iRun).fsEstimate = fsEstimate;
    run(iRun).fNyquistHz = fNyquistEstimate;
    run(iRun).fMaxRequestedHz = fMaxRequested;
    run(iRun).fMaxUsedHz = fMaxUsed;
    run(iRun).autoLimitedFMax = autoLimitedFMax;
    run(iRun).analysisError = analysisError;

    if isfield(meta, "actualSampleRateArduinoHz")
        run(iRun).actualSampleRateArduinoHz = meta.actualSampleRateArduinoHz;
    end

    if isfield(meta, "actualSampleRateMatlabHz")
        run(iRun).actualSampleRateMatlabHz = meta.actualSampleRateMatlabHz;
    end

    if ~isempty(fftResults)
        run(iRun).freqHz = fftResults.freqHz;
        run(iRun).zeta = fftResults.zeta;
        run(iRun).fs = fftResults.fs;
        run(iRun).df = fftResults.df;
    end
end

summary = struct();
summary.method = "Hammer-test batch FFT peak picking";
summary.batchFolder = batchFolder;
summary.filePattern = filePattern;
summary.fileRegex = fileRegex;
summary.createdAt = datetime("now", "TimeZone", "local");
summary.N = N;
summary.files = string(fullfile({files.folder}.', {files.name}.'));
summary.run = run;
summary.autoLimitFMax = autoLimitFMax;
summary.fMaxSafetyFactor = fMaxSafetyFactor;

summary.freqMatrixHz = padNumericRows(freqCells);
summary.zetaMatrix = padNumericRows(zetaCells);
summary.freqMeanHz = mean(summary.freqMatrixHz, 1, "omitnan");
summary.freqStdHz = std(summary.freqMatrixHz, 0, 1, "omitnan");
summary.zetaMean = mean(summary.zetaMatrix, 1, "omitnan");
summary.zetaStd = std(summary.zetaMatrix, 0, 1, "omitnan");
summary.fftOptions = fftOptions;
summary.resultsTable = createResultsTable(summary);

if saveTotalResults
    resultsFile = fullfile(batchFolder, resultsFileName);
    writetable(summary.resultsTable, resultsFile);
    summary.resultsFile = string(resultsFile);

    resultsTextFile = fullfile(batchFolder, resultsTextFileName);
    writeTextResultsFile(resultsTextFile, summary);
    summary.resultsTextFile = string(resultsTextFile);

    if saveMeasurementsFile
        measurementsFile = fullfile(batchFolder, measurementsFileName);
        writeMeasurementsFile(measurementsFile, summary, numMeasurementModes);
        summary.measurementsFile = string(measurementsFile);
        summary.numMeasurementModes = numMeasurementModes;
    end

    if verbose
        fprintf("Saved total FFT results to %s\n", resultsFile);
        fprintf("Saved text results to %s\n", resultsTextFile);

        if saveMeasurementsFile
            fprintf("Saved measurement export to %s\n", measurementsFile);
        end
    end
end

if saveSummary
    summaryFile = fullfile(batchFolder, summaryFileName);
    save(summaryFile, "summary");
    summary.summaryFile = string(summaryFile);

    if verbose
        fprintf("Saved FFT batch summary to %s\n", summaryFile);
    end
end

if verbose
    printSummary(summary);
end

end

%% ========================================================================
% LOCAL HELPER FUNCTIONS
% ========================================================================

function runSummary = createEmptyRunSummary()

runSummary = struct();
runSummary.index = NaN;
runSummary.file = "";
runSummary.numSamples = NaN;
runSummary.actualSampleRateArduinoHz = NaN;
runSummary.actualSampleRateMatlabHz = NaN;
runSummary.fsEstimate = NaN;
runSummary.fNyquistHz = NaN;
runSummary.fMaxRequestedHz = NaN;
runSummary.fMaxUsedHz = NaN;
runSummary.autoLimitedFMax = false;
runSummary.fs = NaN;
runSummary.df = NaN;
runSummary.analysisError = "";
runSummary.freqHz = [];
runSummary.zeta = [];

end

function files = sortFileStructByName(files)

if isempty(files)
    return;
end

[~, idx] = sort({files.name});
files = files(idx);

end

function [fs, fNyquist] = estimateSamplingInfo(T, meta, options)

fs = NaN;
fNyquist = NaN;
[sampleRateOverride, ~] = getNameValueOption(options, "SampleRate", []);
[useNominalSampleRate, ~] = getNameValueOption(options, "UseNominalSampleRate", false);

if logical(useNominalSampleRate)
    fs = chooseNominalSampleRate(T, meta, sampleRateOverride);
else
    t = selectTimeVectorForEstimate(T);

    if ~isempty(t)
        t = double(t(:));
        t = t(isfinite(t));
        t = sort(t);
        t = unique(t, "stable");
        dt = median(diff(t));

        if isfinite(dt) && dt > 0
            fs = 1 / dt;
        end
    end

    if ~isfinite(fs)
        fs = chooseNominalSampleRate(T, meta, sampleRateOverride);
    end
end

if isfinite(fs) && fs > 0
    fNyquist = fs / 2;
end

end

function t = selectTimeVectorForEstimate(T)

varNames = string(T.Properties.VariableNames);

if ismember("t_arduino_elapsed_s", varNames)
    t = T.t_arduino_elapsed_s;
elseif ismember("t_arduino_s", varNames)
    t = T.t_arduino_s - T.t_arduino_s(1);
elseif ismember("t_matlab_elapsed_s", varNames)
    t = T.t_matlab_elapsed_s;
else
    t = [];
end

end

function fs = chooseNominalSampleRate(T, meta, sampleRateOverride)

fs = NaN;

if isnumeric(sampleRateOverride) && isscalar(sampleRateOverride) && sampleRateOverride > 0
    fs = sampleRateOverride;
    return;
end

if isstruct(meta) && isfield(meta, "sampleRate") && isnumeric(meta.sampleRate) && ...
        isscalar(meta.sampleRate) && meta.sampleRate > 0
    fs = meta.sampleRate;
    return;
end

if isstruct(T.Properties.UserData) && isfield(T.Properties.UserData, "sampleRate")
    candidate = T.Properties.UserData.sampleRate;

    if isnumeric(candidate) && isscalar(candidate) && candidate > 0
        fs = candidate;
    end
end

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

function [value, found] = getNameValueOption(options, name, defaultValue)

value = defaultValue;
found = false;
name = string(name);

for i = 1:2:numel(options)
    if string(options{i}) == name
        value = options{i + 1};
        found = true;
        return;
    end
end

end

function options = setNameValueOption(options, name, value)

name = string(name);

for i = 1:2:numel(options)
    if string(options{i}) == name
        options{i + 1} = value;
        return;
    end
end

options(end + 1:end + 2) = {char(name), value};

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

function resultsTable = createResultsTable(summary)

nRuns = numel(summary.run);
maxModes = size(summary.freqMatrixHz, 2);

Run = nan(nRuns, 1);
File = strings(nRuns, 1);
NumSamples = nan(nRuns, 1);
FsHz = nan(nRuns, 1);
DfHz = nan(nRuns, 1);
FsEstimateHz = nan(nRuns, 1);
NyquistHz = nan(nRuns, 1);
FMaxRequestedHz = nan(nRuns, 1);
FMaxUsedHz = nan(nRuns, 1);
AutoLimitedFMax = false(nRuns, 1);
ArduinoSampleRateHz = nan(nRuns, 1);
MatlabSampleRateHz = nan(nRuns, 1);
AnalysisError = strings(nRuns, 1);

for iRun = 1:nRuns
    Run(iRun) = summary.run(iRun).index;
    File(iRun) = summary.run(iRun).file;
    NumSamples(iRun) = summary.run(iRun).numSamples;
    FsHz(iRun) = summary.run(iRun).fs;
    DfHz(iRun) = summary.run(iRun).df;
    FsEstimateHz(iRun) = summary.run(iRun).fsEstimate;
    NyquistHz(iRun) = summary.run(iRun).fNyquistHz;
    FMaxRequestedHz(iRun) = summary.run(iRun).fMaxRequestedHz;
    FMaxUsedHz(iRun) = summary.run(iRun).fMaxUsedHz;
    AutoLimitedFMax(iRun) = summary.run(iRun).autoLimitedFMax;
    ArduinoSampleRateHz(iRun) = summary.run(iRun).actualSampleRateArduinoHz;
    MatlabSampleRateHz(iRun) = summary.run(iRun).actualSampleRateMatlabHz;
    AnalysisError(iRun) = summary.run(iRun).analysisError;
end

resultsTable = table( ...
    Run, ...
    File, ...
    NumSamples, ...
    FsHz, ...
    DfHz, ...
    FsEstimateHz, ...
    NyquistHz, ...
    FMaxRequestedHz, ...
    FMaxUsedHz, ...
    AutoLimitedFMax, ...
    ArduinoSampleRateHz, ...
    MatlabSampleRateHz, ...
    AnalysisError);

for iMode = 1:maxModes
    resultsTable.(sprintf("freq_%02d_Hz", iMode)) = summary.freqMatrixHz(:, iMode);
end

for iMode = 1:maxModes
    resultsTable.(sprintf("zeta_%02d", iMode)) = summary.zetaMatrix(:, iMode);
end

end

function writeTextResultsFile(resultsTextFile, summary)

fid = fopen(resultsTextFile, "w");

if fid < 0
    error("Could not open results text file %s.", resultsTextFile);
end

cleanupObj = onCleanup(@() fclose(fid));

fprintf(fid, "Hammer-test FFT peak-picking results\n");
fprintf(fid, "Created: %s\n", char(summary.createdAt));
fprintf(fid, "Folder: %s\n", summary.batchFolder);
fprintf(fid, "Number of measurements: %d\n\n", summary.N);

fprintf(fid, "Per-measurement results:\n");

for iRun = 1:summary.N
    fprintf(fid, "Sample:%3d  Fs: %8.3f Hz  FMax used: %8.3f Hz  freq(Hz):", ...
        iRun, summary.run(iRun).fs, summary.run(iRun).fMaxUsedHz);
    fprintf(fid, " %+10.5f", summary.freqMatrixHz(iRun, :));
    fprintf(fid, "  zeta(-):");
    fprintf(fid, " %+10.5f", summary.zetaMatrix(iRun, :));

    if strlength(summary.run(iRun).analysisError) > 0
        fprintf(fid, "  ERROR: %s", summary.run(iRun).analysisError);
    end

    fprintf(fid, "\n");
end

fprintf(fid, "\nTotal results:\n");
fprintf(fid, "Mean freq(Hz):");
fprintf(fid, " %+10.5f", summary.freqMeanHz);
fprintf(fid, "\nStd  freq(Hz):");
fprintf(fid, " %+10.5f", summary.freqStdHz);
fprintf(fid, "\nMean zeta(-):");
fprintf(fid, " %+10.5f", summary.zetaMean);
fprintf(fid, "\nStd  zeta(-):");
fprintf(fid, " %+10.5f", summary.zetaStd);
fprintf(fid, "\n");

end

function writeMeasurementsFile(measurementsFile, summary, numModes)

fid = fopen(measurementsFile, "w");

if fid < 0
    error("Could not open measurements text file %s.", measurementsFile);
end

cleanupObj = onCleanup(@() fclose(fid));
freqMatrix = firstNColumns(summary.freqMatrixHz, numModes);
zetaMatrix = firstNColumns(summary.zetaMatrix, numModes);

for iRun = 1:summary.N
    fprintf(fid, "%4d", summary.run(iRun).index);

    for iMode = 1:numModes
        writeSignedFixedValue(fid, freqMatrix(iRun, iMode));
    end

    for iMode = 1:numModes
        writeSignedFixedValue(fid, zetaMatrix(iRun, iMode));
    end

    fprintf(fid, " \n");
end

end

function value = firstNColumns(value, nColumns)

nRows = size(value, 1);
nExistingColumns = size(value, 2);
value(:, nExistingColumns + 1:nColumns) = NaN;
value = value(:, 1:nColumns);

if nRows == 0
    value = nan(0, nColumns);
end

end

function writeSignedFixedValue(fid, value)

if isfinite(value)
    fprintf(fid, " %+.8f", value);
else
    fprintf(fid, " NaN");
end

end

function printSummary(summary)

fprintf("\nHammer-test FFT peak-picking summary:\n");

if isempty(summary.freqMeanHz) || all(isnan(summary.freqMeanHz))
    fprintf("  No valid frequencies were estimated.\n");
    printAnalysisErrors(summary);
    return;
end

for iMode = 1:numel(summary.freqMeanHz)
    fprintf("  Mode %2d: f = %10.5f Hz +/- %10.5f Hz, zeta = %10.5f +/- %10.5f\n", ...
        iMode, ...
        summary.freqMeanHz(iMode), ...
        summary.freqStdHz(iMode), ...
        summary.zetaMean(iMode), ...
        summary.zetaStd(iMode));
end

printAnalysisErrors(summary);

end

function printAnalysisErrors(summary)

errors = strings(0, 1);

for iRun = 1:numel(summary.run)
    if strlength(summary.run(iRun).analysisError) > 0
        errors(end + 1, 1) = summary.run(iRun).analysisError; %#ok<AGROW>
    end
end

if isempty(errors)
    return;
end

errors = unique(errors, "stable");
fprintf("  Analysis warnings/errors:\n");

for iErr = 1:numel(errors)
    fprintf("    - %s\n", errors(iErr));
end

end
