function batch = FinalizeShakeTableFRFBatch(batchSource, varargin)
% FinalizeShakeTableFRFBatch
%
% Rebuilds a shaking-table modal summary from already saved run files.
% No serial port is opened and no new motion or acquisition is started.

parser = inputParser;
parser.FunctionName = mfilename;
addParameter(parser, "OutputFile", "", @(x) ischar(x) || isstring(x));
parse(parser, varargin{:});

batchSource = string(batchSource);

if isfolder(batchSource)
    summaryFile = fullfile(batchSource, ...
        "shake_table_frf_setup_summary.mat");
else
    summaryFile = batchSource;
end

if ~isfile(summaryFile)
    error("Batch summary file does not exist: %s", summaryFile);
end

savedSummary = load(summaryFile, "batch");

if ~isfield(savedSummary, "batch") || ~isstruct(savedSummary.batch)
    error("The selected file does not contain a valid batch structure.");
end

batch = savedSummary.batch;

if ~isfield(batch, "run") || ~isfield(batch, "settings")
    error("The batch structure does not contain run and settings metadata.");
end

nRuns = numel(batch.run);
frfCells = cell(nRuns, 1);
qualityUsableRunMask = false(nRuns, 1);

for iRun = 1:nRuns
    runFile = resolveRunFile(batch, iRun);

    if strlength(runFile) == 0 || ~isfile(runFile)
        warning("FinalizeShakeTableFRFBatch:MissingRunFile", ...
            "Run %d could not be loaded from %s.", iRun, runFile);
        continue;
    end

    savedRun = load(runFile, "frfResults", "meta");

    if isfield(savedRun, "frfResults") && isstruct(savedRun.frfResults)
        frfCells{iRun} = savedRun.frfResults;
    end

    if isfield(savedRun, "meta") && isstruct(savedRun.meta) && ...
            isfield(savedRun.meta, "quality") && ...
            isfield(savedRun.meta.quality, "usableForBatchSummary")
        qualityUsableRunMask(iRun) = logical( ...
            savedRun.meta.quality.usableForBatchSummary);
    elseif isfield(batch.run(iRun), "usableForBatchSummary")
        qualityUsableRunMask(iRun) = logical( ...
            batch.run(iRun).usableForBatchSummary);
    end
end

settings = batch.settings;
modalSummary = SummarizeShakeTableFRFRuns( ...
    frfCells, qualityUsableRunMask, ...
    "NumSensors", settings.NumSensors, ...
    "ModeMatchToleranceHz", settings.ModeMatchToleranceHz, ...
    "MinModeOccurrenceFraction", settings.MinModeOccurrenceFraction, ...
    "ReferenceFrequenciesHz", settings.ReferenceFrequenciesHz, ...
    "StartFrequencyHz", settings.StartFrequencyHz, ...
    "EndFrequencyHz", settings.EndFrequencyHz, ...
    "ReferenceMatchToleranceHz", settings.ReferenceMatchToleranceHz);

batch.modalSummary = modalSummary;
batch.qualityUsableRunMask = modalSummary.qualityUsableRunMask;
batch.analysisAvailableRunMask = modalSummary.analysisAvailableRunMask;
batch.includedRunMask = modalSummary.includedRunMask;
batch.numQualityUsableRuns = modalSummary.numQualityUsableRuns;
batch.numIncludedRuns = modalSummary.numIncludedRuns;
batch.freqMatrixHz = modalSummary.freqMatrixHz;
batch.zetaMatrix = modalSummary.zetaMatrix;
batch.modeInfo = modalSummary.modeInfo;
batch.freqMeanHz = modalSummary.freqMeanHz;
batch.freqStdHz = modalSummary.freqStdHz;
batch.zetaMean = modalSummary.zetaMean;
batch.zetaStd = modalSummary.zetaStd;
batch.modeShapeRunsNormalizedComplex = ...
    modalSummary.modeShapeRunsNormalizedComplex;
batch.modeShapeMeanNormalizedComplex = ...
    modalSummary.modeShapeMeanNormalizedComplex;
batch.modeShapeMeanAmplitude = modalSummary.modeShapeMeanAmplitude;
batch.modeShapeMeanPhaseDeg = modalSummary.modeShapeMeanPhaseDeg;
batch.referenceComparison = modalSummary.referenceComparison;
batch.summaryFinalizedAt = datetime("now", "TimeZone", "local");

outputFile = string(parser.Results.OutputFile);

if strlength(outputFile) == 0
    outputFile = fullfile(fileparts(summaryFile), ...
        "shake_table_frf_setup_summary_recovered.mat");
end

batch.summaryFile = outputFile;
save(outputFile, "batch");

fprintf("Recovered summary from %d/%d eligible runs.\n", ...
    batch.numIncludedRuns, nRuns);
fprintf("Saved recovered summary to %s\n", outputFile);

if height(batch.modeInfo) == 0
    fprintf("No repeatable FRF peaks passed the occurrence settings.\n");
else
    disp(batch.modeInfo);
end

end

function runFile = resolveRunFile(batch, iRun)

runFile = "";

if isfield(batch, "files") && numel(batch.files) >= iRun
    runFile = string(batch.files(iRun));
end

if (strlength(runFile) == 0 || ~isfile(runFile)) && ...
        isfield(batch.run(iRun), "file")
    runFile = string(batch.run(iRun).file);
end

end
