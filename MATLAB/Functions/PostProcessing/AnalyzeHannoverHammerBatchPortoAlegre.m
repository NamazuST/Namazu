function summary = AnalyzeHannoverHammerBatchPortoAlegre( ...
    sourceFolder, outputFolder, varargin)
% AnalyzeHannoverHammerBatchPortoAlegre
%
% Applies the Porto Alegre per-record modal extraction to the Hannover raw
% hammer-test data. Because the Hannover spectra can contain more than four
% qualifying peaks, recurrent structural modes are associated only after
% the Porto-style extraction. All raw detected peaks are retained for audit.

parser = inputParser;
parser.FunctionName = mfilename;
addParameter(parser, "StructuralSensors", [5, 4, 3, 2], ...
    @(x) isnumeric(x) && isvector(x) && numel(x) == 4);
addParameter(parser, "Direction", "y", ...
    @(x) ischar(x) || isstring(x));
addParameter(parser, "UseCorrectedSignals", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "Gravity", 9.81, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "RelativePeakLevel", 0.03, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "MinPeakDistanceHz", 15, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "DeltaFInterpHz", 5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "InterpolationPoints", 5000, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 3);
addParameter(parser, "AssociationFMaxHz", 100, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "ModeMatchToleranceHz", 3, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "MinModeOccurrenceFraction", ...
    0.90 + 10 * eps(0.90), ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(parser, "ExpectedModes", 4, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 1 && mod(x, 1) == 0);
addParameter(parser, "ComputeDamping", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "MakePlots", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "Verbose", true, ...
    @(x) islogical(x) || isnumeric(x));
parse(parser, varargin{:});

sourceFolder = string(sourceFolder);
outputFolder = string(outputFolder);
structuralSensors = double(parser.Results.StructuralSensors(:).');
direction = string(parser.Results.Direction);
useCorrectedSignals = logical(parser.Results.UseCorrectedSignals);
gravity = parser.Results.Gravity;
relativePeakLevel = parser.Results.RelativePeakLevel;
minPeakDistanceHz = parser.Results.MinPeakDistanceHz;
deltaFInterpHz = parser.Results.DeltaFInterpHz;
interpolationPoints = parser.Results.InterpolationPoints;
associationFMaxHz = parser.Results.AssociationFMaxHz;
modeMatchToleranceHz = parser.Results.ModeMatchToleranceHz;
minModeOccurrenceFraction = ...
    parser.Results.MinModeOccurrenceFraction;
expectedModes = parser.Results.ExpectedModes;
computeDamping = logical(parser.Results.ComputeDamping);
makePlots = logical(parser.Results.MakePlots);
verbose = logical(parser.Results.Verbose);

if ~isfolder(sourceFolder)
    error("Hannover source folder not found:\n%s", sourceFolder);
end

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

files = dir(fullfile(sourceFolder, "hammer_test_*.mat"));
files = files(~[files.isdir]);
keep = ~cellfun("isempty", regexp( ...
    {files.name}, "^hammer_test_\d+\.mat$", "once"));
files = files(keep);
files = sortHammerFiles(files);
numberOfRuns = numel(files);

if numberOfRuns == 0
    error("No Hannover hammer_test_NNN.mat files found.");
end

frequencyCells = cell(numberOfRuns, 1);
dampingCells = cell(numberOfRuns, 1);
rawFrequencyCells = cell(numberOfRuns, 1);
rawDampingCells = cell(numberOfRuns, 1);
rawPeakValueCells = cell(numberOfRuns, 1);
runAnalysis = cell(numberOfRuns, 1);
numberOfSamples = nan(numberOfRuns, 1);
sampleRateHz = nan(numberOfRuns, 1);
durationSeconds = nan(numberOfRuns, 1);
durationResolutionHz = nan(numberOfRuns, 1);
fftAxisSpacingHz = nan(numberOfRuns, 1);
detectedPeakCount = zeros(numberOfRuns, 1);
associatedPeakCount = zeros(numberOfRuns, 1);
qualityUsable = true(numberOfRuns, 1);
analysisError = strings(numberOfRuns, 1);
maxAbsStructuralG = nan(numberOfRuns, 1);
channelInfo = struct();

for iRun = 1:numberOfRuns
    filePath = fullfile(files(iRun).folder, files(iRun).name);

    if verbose
        fprintf("Porto-style Hannover analysis %d/%d: %s\n", ...
            iRun, numberOfRuns, files(iRun).name);
    end

    saved = load(filePath);

    if isfield(saved, "T") && istable(saved.T)
        T = saved.T;
    elseif isfield(saved, "sensorRigData") && istable(saved.sensorRigData)
        T = saved.sensorRigData;
    else
        analysisError(iRun) = "No sensor-rig table found.";
        continue;
    end

    if isfield(saved, "meta") && isstruct(saved.meta) && ...
            isfield(saved.meta, "quality") && ...
            isfield(saved.meta.quality, "usableForAnalysis")
        qualityUsable(iRun) = ...
            logical(saved.meta.quality.usableForAnalysis);
    end

    try
        [time, acceleration, channelInfo] = ...
            ExtractHannoverChannelsPortoAlegre(T, ...
            "StructuralSensors", structuralSensors, ...
            "Direction", direction, ...
            "UseCorrectedSignals", useCorrectedSignals, ...
            "Gravity", gravity);
        result = EstimateModalParametersPortoAlegre( ...
            time, acceleration, ...
            "RelativePeakLevel", relativePeakLevel, ...
            "MinPeakDistanceHz", minPeakDistanceHz, ...
            "DeltaFInterpHz", deltaFInterpHz, ...
            "InterpolationPoints", interpolationPoints, ...
            "DampingChannel", 4, ...
            "ComputeDamping", computeDamping, ...
            "MakePlots", false);

        rawFrequencyCells{iRun} = result.freqHz;
        rawDampingCells{iRun} = result.zeta;
        rawPeakValueCells{iRun} = result.refinedPeakValues;
        runAnalysis{iRun} = result;
        detectedPeakCount(iRun) = result.numberOfPeaks;
        numberOfSamples(iRun) = result.numberOfSamples;
        sampleRateHz(iRun) = result.fs;
        durationSeconds(iRun) = result.measurementDuration;
        durationResolutionHz(iRun) = result.dfDuration;
        fftAxisSpacingHz(iRun) = result.fftAxisSpacingHz;
        maxAbsStructuralG(iRun) = ...
            max(abs(acceleration / gravity), [], "all");

        associationMask = result.freqHz <= associationFMaxHz;
        frequencyCells{iRun} = result.freqHz(associationMask);
        dampingCells{iRun} = result.zeta(associationMask);
        associatedPeakCount(iRun) = nnz(associationMask);
    catch ME
        analysisError(iRun) = string(ME.message);

        if verbose
            warning("AnalyzeHannoverHammerBatchPortoAlegre:RunFailed", ...
                "Run %d failed: %s", iRun, ME.message);
        end
    end
end

includedRuns = qualityUsable & strlength(analysisError) == 0;
[frequencyMatrixHz, dampingMatrix, modeInfo] = ...
    MatchModalPeaksAcrossRuns( ...
    frequencyCells, ...
    dampingCells, ...
    "ToleranceHz", modeMatchToleranceHz, ...
    "MinOccurrenceFraction", minModeOccurrenceFraction, ...
    "IncludedRuns", includedRuns);

if size(frequencyMatrixHz, 2) ~= expectedModes
    warning("Expected %d recurrent modes, but found %d.", ...
        expectedModes, size(frequencyMatrixHz, 2));
end

frequencyMeanHz = mean(frequencyMatrixHz, 1, "omitnan");
frequencyStdHz = std(frequencyMatrixHz, 0, 1, "omitnan");
dampingMean = mean(dampingMatrix, 1, "omitnan");
dampingStd = std(dampingMatrix, 0, 1, "omitnan");
frequencyCovarianceHz2 = cov(frequencyMatrixHz, "partialrows");
dampingCovariance = cov(dampingMatrix, "partialrows");

runTable = createRunTable( ...
    files, ...
    numberOfSamples, ...
    sampleRateHz, ...
    durationSeconds, ...
    durationResolutionHz, ...
    fftAxisSpacingHz, ...
    detectedPeakCount, ...
    associatedPeakCount, ...
    qualityUsable, ...
    maxAbsStructuralG, ...
    analysisError, ...
    frequencyMatrixHz, ...
    dampingMatrix);
rawPeakTable = createRawPeakTable( ...
    rawFrequencyCells, ...
    rawDampingCells, ...
    rawPeakValueCells, ...
    associationFMaxHz);

summary = struct();
summary.method = ...
    "Porto Alegre per-record FFT extraction adapted to Hannover";
summary.createdAt = datetime("now", "TimeZone", "local");
summary.sourceFolder = sourceFolder;
summary.outputFolder = outputFolder;
summary.numberOfRuns = numberOfRuns;
summary.files = string(fullfile({files.folder}.', {files.name}.'));
summary.channelInfo = channelInfo;
summary.rawFrequencyCells = rawFrequencyCells;
summary.rawDampingCells = rawDampingCells;
summary.rawPeakValueCells = rawPeakValueCells;
summary.runAnalysis = runAnalysis;
summary.frequencyMatrixHz = frequencyMatrixHz;
summary.dampingMatrix = dampingMatrix;
summary.modeInfo = modeInfo;
summary.frequencyMeanHz = frequencyMeanHz;
summary.frequencyStdHz = frequencyStdHz;
summary.dampingMean = dampingMean;
summary.dampingStd = dampingStd;
summary.frequencyCovarianceHz2 = frequencyCovarianceHz2;
summary.dampingCovariance = dampingCovariance;
summary.runTable = runTable;
summary.rawPeakTable = rawPeakTable;
summary.settings = struct( ...
    "structuralSensorsPortoOrder", structuralSensors, ...
    "direction", direction, ...
    "useCorrectedSignals", useCorrectedSignals, ...
    "gravity", gravity, ...
    "relativePeakLevel", relativePeakLevel, ...
    "minPeakDistanceHz", minPeakDistanceHz, ...
    "deltaFInterpHz", deltaFInterpHz, ...
    "interpolationMethod", "spline", ...
    "interpolationPoints", interpolationPoints, ...
    "spectrumWindow", "rectangular", ...
    "zeroPadding", false, ...
    "associationFMaxHz", associationFMaxHz, ...
    "modeMatchToleranceHz", modeMatchToleranceHz, ...
    "minModeOccurrenceFraction", minModeOccurrenceFraction, ...
    "computeDamping", computeDamping);

%% -------------------- EXPORTS --------------------
measurementsFile = fullfile(outputFolder, "measurements.txt");
resultsFile = fullfile(outputFolder, "results.txt");
csvFile = fullfile(outputFolder, "porto_style_results.csv");
rawPeakFile = fullfile(outputFolder, "raw_detected_peaks.csv");
modeFile = fullfile(outputFolder, "mode_summary.csv");
frequencyCovarianceFile = fullfile( ...
    outputFolder, "frequency_covariance_Hz2.csv");
dampingCovarianceFile = fullfile( ...
    outputFolder, "damping_covariance.csv");
summaryFile = fullfile(outputFolder, "porto_style_summary.mat");
reportFile = fullfile(outputFolder, "analysis_report.txt");
differencesFile = fullfile(outputFolder, "dataset_differences.txt");

writePortoMeasurements( ...
    measurementsFile, frequencyMatrixHz, dampingMatrix);
writePortoMeasurements(resultsFile, frequencyMatrixHz, dampingMatrix);
writetable(runTable, csvFile);
writetable(rawPeakTable, rawPeakFile);
writetable(createModeTable(summary), modeFile);
writematrix(frequencyCovarianceHz2, frequencyCovarianceFile);
writematrix(dampingCovariance, dampingCovarianceFile);
writeAnalysisReport(reportFile, summary, detectedPeakCount);
writeDatasetDifferences(differencesFile, summary);
save(summaryFile, "summary");

summary.filesWritten = string([ ...
    measurementsFile
    resultsFile
    csvFile
    rawPeakFile
    modeFile
    frequencyCovarianceFile
    dampingCovarianceFile
    summaryFile
    reportFile
    differencesFile]);

if makePlots
    summary.plotFiles = createSummaryPlots(outputFolder, summary);
else
    summary.plotFiles = strings(0, 1);
end

save(summaryFile, "summary");

if verbose
    fprintf("\nPorto-style Hannover recurrent modes:\n");
    disp(modeInfo);
    fprintf("Mean frequencies [Hz]:");
    fprintf(" %.8f", frequencyMeanHz);
    fprintf("\nStandard deviations [Hz]:");
    fprintf(" %.8f", frequencyStdHz);
    fprintf("\nStrictly four detected peaks: %d/%d runs\n", ...
        nnz(detectedPeakCount == expectedModes), numberOfRuns);
    fprintf("Saved output to:\n  %s\n", outputFolder);
end

end

function files = sortHammerFiles(files)

indices = nan(numel(files), 1);

for iFile = 1:numel(files)
    token = regexp(files(iFile).name, ...
        "^hammer_test_(\d+)\.mat$", "tokens", "once");
    indices(iFile) = str2double(token{1});
end

[~, order] = sort(indices);
files = files(order);

end

function runTable = createRunTable( ...
    files, numberOfSamples, sampleRateHz, durationSeconds, ...
    durationResolutionHz, fftAxisSpacingHz, detectedPeakCount, ...
    associatedPeakCount, qualityUsable, maxAbsStructuralG, analysisError, ...
    frequencyMatrixHz, dampingMatrix)

numberOfRuns = numel(files);
Run = (1:numberOfRuns).';
File = string({files.name}.');
runTable = table( ...
    Run, ...
    File, ...
    numberOfSamples, ...
    sampleRateHz, ...
    durationSeconds, ...
    durationResolutionHz, ...
    fftAxisSpacingHz, ...
    detectedPeakCount, ...
    associatedPeakCount, ...
    qualityUsable, ...
    maxAbsStructuralG, ...
    analysisError, ...
    'VariableNames', { ...
    'Run', ...
    'File', ...
    'NumberOfSamples', ...
    'SampleRateHz', ...
    'DurationSeconds', ...
    'DurationResolutionHz', ...
    'FFTAxisSpacingHz', ...
    'DetectedPeakCount', ...
    'PeaksAtOrBelowAssociationFMax', ...
    'QualityUsable', ...
    'MaxAbsStructuralG', ...
    'AnalysisError'});

for iMode = 1:size(frequencyMatrixHz, 2)
    runTable.(sprintf("f%d_Hz", iMode)) = frequencyMatrixHz(:, iMode);
end

for iMode = 1:size(dampingMatrix, 2)
    runTable.(sprintf("zeta%d", iMode)) = dampingMatrix(:, iMode);
end

end

function rawPeakTable = createRawPeakTable( ...
    frequencyCells, dampingCells, peakValueCells, associationFMaxHz)

numberOfRows = sum(cellfun(@numel, frequencyCells));
Run = nan(numberOfRows, 1);
Peak = nan(numberOfRows, 1);
FrequencyHz = nan(numberOfRows, 1);
DampingRatio = nan(numberOfRows, 1);
RefinedPeakValue = nan(numberOfRows, 1);
InsideAssociationBand = false(numberOfRows, 1);
row = 0;

for iRun = 1:numel(frequencyCells)
    frequencies = frequencyCells{iRun};
    damping = dampingCells{iRun};
    peakValues = peakValueCells{iRun};

    for iPeak = 1:numel(frequencies)
        row = row + 1;
        Run(row) = iRun;
        Peak(row) = iPeak;
        FrequencyHz(row) = frequencies(iPeak);

        if iPeak <= numel(damping)
            DampingRatio(row) = damping(iPeak);
        end

        if iPeak <= numel(peakValues)
            RefinedPeakValue(row) = peakValues(iPeak);
        end

        InsideAssociationBand(row) = ...
            frequencies(iPeak) <= associationFMaxHz;
    end
end

rawPeakTable = table( ...
    Run, ...
    Peak, ...
    FrequencyHz, ...
    DampingRatio, ...
    RefinedPeakValue, ...
    InsideAssociationBand);

end

function modeTable = createModeTable(summary)

Mode = summary.modeInfo.Mode;
CenterHz = summary.modeInfo.CenterHz;
OccurrenceCount = summary.modeInfo.OccurrenceCount;
OccurrenceFraction = summary.modeInfo.OccurrenceFraction;
MeanFrequencyHz = summary.frequencyMeanHz(:);
StdFrequencyHz = summary.frequencyStdHz(:);
MeanDampingRatio = summary.dampingMean(:);
StdDampingRatio = summary.dampingStd(:);
modeTable = table( ...
    Mode, ...
    CenterHz, ...
    OccurrenceCount, ...
    OccurrenceFraction, ...
    MeanFrequencyHz, ...
    StdFrequencyHz, ...
    MeanDampingRatio, ...
    StdDampingRatio);

end

function writePortoMeasurements(filePath, frequencyMatrix, dampingMatrix)

fileId = fopen(filePath, "w");

if fileId < 0
    error("Could not open output file:\n%s", filePath);
end

cleanupObj = onCleanup(@() fclose(fileId));
numberOfRuns = size(frequencyMatrix, 1);
numberOfModes = size(frequencyMatrix, 2);

for iRun = 1:numberOfRuns
    fprintf(fileId, " %3d", iRun);

    for iMode = 1:numberOfModes
        writeSignedValue(fileId, frequencyMatrix(iRun, iMode));
    end

    for iMode = 1:numberOfModes
        writeSignedValue(fileId, dampingMatrix(iRun, iMode));
    end

    fprintf(fileId, " \n");
end

clear cleanupObj;

end

function writeSignedValue(fileId, value)

if isfinite(value)
    fprintf(fileId, " %+.8f", value);
else
    fprintf(fileId, " NaN");
end

end

function writeAnalysisReport(filePath, summary, detectedPeakCount)

fileId = fopen(filePath, "w");

if fileId < 0
    error("Could not open analysis report:\n%s", filePath);
end

cleanupObj = onCleanup(@() fclose(fileId));
settings = summary.settings;

fprintf(fileId, "Hannover hammer tests processed with the Porto Alegre method\n");
fprintf(fileId, "Created: %s\n", char(summary.createdAt));
fprintf(fileId, "Source: %s\n", summary.sourceFolder);
fprintf(fileId, "Runs: %d\n\n", summary.numberOfRuns);
fprintf(fileId, "Porto-identical per-record steps:\n");
fprintf(fileId, "  Four structural response channels\n");
fprintf(fileId, "  Mean removal\n");
fprintf(fileId, "  Rectangular unpadded FFT\n");
fprintf(fileId, "  Maximum four-channel spectral envelope\n");
fprintf(fileId, "  Relative peak threshold: %.4f\n", ...
    settings.relativePeakLevel);
fprintf(fileId, "  Minimum peak distance: %.3f Hz\n", ...
    settings.minPeakDistanceHz);
fprintf(fileId, "  Cubic-spline interval: +/-%.3f Hz\n", ...
    settings.deltaFInterpHz);
fprintf(fileId, "  Spline evaluation points: %d\n", ...
    settings.interpolationPoints);
fprintf(fileId, "  Damping reference: structural channel 4 / Hannover sensor 2\n");
fprintf(fileId, "  Damping interval: 1 to 30 modal cycles\n\n");
fprintf(fileId, "Hannover adapter:\n");
fprintf(fileId, "  Structural sensor order: ");
fprintf(fileId, "%d ", settings.structuralSensorsPortoOrder);
fprintf(fileId, "(Porto DoF 1 to 4)\n");
fprintf(fileId, "  Corrected digital g values converted with g = %.3f m/s^2\n", ...
    settings.gravity);
fprintf(fileId, "  Mode-association upper bound: %.3f Hz\n", ...
    settings.associationFMaxHz);
fprintf(fileId, "  Cross-run association tolerance: %.3f Hz\n", ...
    settings.modeMatchToleranceHz);
fprintf(fileId, "  Association is bookkeeping required because Hannover has\n");
fprintf(fileId, "  more than four qualifying peaks in many records; it is not\n");
fprintf(fileId, "  part of the Porto per-record frequency estimator.\n\n");
fprintf(fileId, "Detected peak counts:\n");

uniqueCounts = unique(detectedPeakCount);

for count = uniqueCounts(:).'
    fprintf(fileId, "  %d peaks: %d runs\n", ...
        count, nnz(detectedPeakCount == count));
end

fprintf(fileId, "\nRecurrent modes:\n");
modeTable = createModeTable(summary);

for iMode = 1:height(modeTable)
    fprintf(fileId, ...
        "  Mode %d: %.8f +/- %.8f Hz, occurrence %d/%d\n", ...
        modeTable.Mode(iMode), ...
        modeTable.MeanFrequencyHz(iMode), ...
        modeTable.StdFrequencyHz(iMode), ...
        modeTable.OccurrenceCount(iMode), ...
        summary.numberOfRuns);
end

clear cleanupObj;

end

function writeDatasetDifferences(filePath, summary)

fileId = fopen(filePath, "w");

if fileId < 0
    error("Could not open dataset-difference report:\n%s", filePath);
end

cleanupObj = onCleanup(@() fclose(fileId));
runTable = summary.runTable;

fprintf(fileId, "Major differences: Porto Alegre (BR) vs Hannover (DE)\n\n");
fprintf(fileId, "Specimen and campaign\n");
fprintf(fileId, "  BR: Same 4-DoF structural concept; fixed base clamped to a rigid\n");
fprintf(fileId, "      wooden table. Measurements were made in blocks of 10, with\n");
fprintf(fileId, "      different operators/days and setup disassembly/reassembly.\n");
fprintf(fileId, "  DE: Hannover campaign kept supports, sensors, cables, impact point\n");
fprintf(fileId, "      and direction unchanged; rejected acquisitions were replaced\n");
fprintf(fileId, "      until 100 quality-usable records were available.\n\n");

fprintf(fileId, "Excitation and sensor layout\n");
fprintf(fileId, "  BR: Manual impact at DoF 4 (bottom mass); four accelerometers,\n");
fprintf(fileId, "      one at each moving mass.\n");
fprintf(fileId, "  DE: Manual impact at Hannover sensor 2 / bottom mass; five sensors\n");
fprintf(fileId, "      were acquired. Sensor 1 is the base/reference and is excluded\n");
fprintf(fileId, "      here; sensors 5,4,3,2 map to Porto DoFs 1,2,3,4.\n\n");

fprintf(fileId, "Transducers and acquisition\n");
fprintf(fileId, "  BR: Four analogue ADXL203 accelerometers, +/-1.7 g, stated\n");
fprintf(fileId, "      0-2 kHz bandwidth, attached with beeswax; Measurement Computing\n");
fprintf(fileId, "      USB-1208FS, four differential channels, 12 bit, +/-5 V;\n");
fprintf(fileId, "      Agilent Vee 4.0 acquisition.\n");
fprintf(fileId, "  DE: Five digital MPU6050 accelerometers, +/-8 g, approximately\n");
fprintf(fileId, "      94 Hz digital low-pass bandwidth, 4096 LSB/g; ESP32/I2C rig\n");
fprintf(fileId, "      streamed over serial to MATLAB.\n\n");

fprintf(fileId, "Calibration and stored data\n");
fprintf(fileId, "  BR: Separate two-column time/voltage .dat file per sensor;\n");
fprintf(fileId, "      sensitivities [0.1072 0.1320 0.1276 0.1329] V/g and zero\n");
fprintf(fileId, "      set points were applied in post-processing.\n");
fprintf(fileId, "  DE: One MAT table per realization containing all axes and sensors\n");
fprintf(fileId, "      in g. A separate 30 s quiet baseline supplied channel offsets;\n");
fprintf(fileId, "      corrected y-axis data are converted to m/s^2 here.\n\n");

fprintf(fileId, "Sampling and record duration\n");
fprintf(fileId, "  BR: fs = 600 Hz, N = 6000, T = 9.998333 s,\n");
fprintf(fileId, "      duration-based df = 0.100017 Hz.\n");
fprintf(fileId, "  DE: fs range %.6f to %.6f Hz; N range %d to %d;\n", ...
    min(runTable.SampleRateHz, [], "omitnan"), ...
    max(runTable.SampleRateHz, [], "omitnan"), ...
    min(runTable.NumberOfSamples, [], "omitnan"), ...
    max(runTable.NumberOfSamples, [], "omitnan"));
fprintf(fileId, "      T range %.6f to %.6f s; duration-based df range\n", ...
    min(runTable.DurationSeconds, [], "omitnan"), ...
    max(runTable.DurationSeconds, [], "omitnan"));
fprintf(fileId, "      %.6f to %.6f Hz.\n\n", ...
    min(runTable.DurationResolutionHz, [], "omitnan"), ...
    max(runTable.DurationResolutionHz, [], "omitnan"));

fprintf(fileId, "Post-processing alignment\n");
fprintf(fileId, "  Identical meaningful choices: four structural channels, channel\n");
fprintf(fileId, "  mean removal, rectangular unpadded FFT, maximum spectral envelope,\n");
fprintf(fileId, "  3%% peak threshold, 15 Hz separation, cubic spline over +/-5 Hz\n");
fprintf(fileId, "  with 5000 points, and channel-4 free-decay damping.\n");
fprintf(fileId, "  Unavoidable differences: voltage calibration versus already digital\n");
fprintf(fileId, "  acceleration, native fs/N/T, sensor bandwidth/range/noise, and a\n");
fprintf(fileId, "  post-extraction association step for the extra Hannover peaks.\n\n");

fprintf(fileId, "Reference-source consistency note\n");
fprintf(fileId, "  The Porto readme/model4DoF.m state 112.2 g per mass, while page 1\n");
fprintf(fileId, "  of 'Figure and test bench.pdf' states 122.2 g. This should be\n");
fprintf(fileId, "  resolved before reporting the nominal mass in the manuscript.\n");

clear cleanupObj;

end

function plotFiles = createSummaryPlots(outputFolder, summary)

frequencyMatrix = summary.frequencyMatrixHz;
dampingMatrix = summary.dampingMatrix;
numberOfModes = size(frequencyMatrix, 2);

frequencyFigure = figure( ...
    "Name", "Porto-style Hannover frequency distributions", ...
    "Color", "w", ...
    "Visible", "off");
tiledlayout(2, numberOfModes, "TileSpacing", "compact");

for iMode = 1:numberOfModes
    nexttile(iMode);
    histogram(frequencyMatrix(:, iMode), "Normalization", "pdf");
    hold on;
    finiteFrequency = frequencyMatrix(isfinite( ...
        frequencyMatrix(:, iMode)), iMode);

    if numel(finiteFrequency) >= 2
        [density, points] = ksdensity(finiteFrequency);
        plot(points, density, "r", "LineWidth", 1.5);
    end

    grid on;
    xlabel(sprintf("f_%d [Hz]", iMode));
    ylabel("PDF");

    nexttile(numberOfModes + iMode);
    histogram(dampingMatrix(:, iMode), "Normalization", "pdf");
    hold on;
    finiteDamping = dampingMatrix(isfinite(dampingMatrix(:, iMode)), iMode);

    if numel(finiteDamping) >= 2
        [density, points] = ksdensity(finiteDamping);
        plot(points, density, "r", "LineWidth", 1.5);
    end

    grid on;
    xlabel(sprintf("zeta_%d [-]", iMode));
    ylabel("PDF");
end

frequencyPlotFile = fullfile( ...
    outputFolder, "porto_style_distributions.png");
exportgraphics(frequencyFigure, frequencyPlotFile, "Resolution", 180);
close(frequencyFigure);

scatterFigure = figure( ...
    "Name", "Porto-style Hannover frequency scatter", ...
    "Color", "w", ...
    "Visible", "off");
plotmatrix(frequencyMatrix);
sgtitle("Hannover modal-frequency observations - Porto Alegre method");
scatterPlotFile = fullfile( ...
    outputFolder, "porto_style_frequency_scatter.png");
exportgraphics(scatterFigure, scatterPlotFile, "Resolution", 180);
close(scatterFigure);

plotFiles = string([frequencyPlotFile; scatterPlotFile]);

end
