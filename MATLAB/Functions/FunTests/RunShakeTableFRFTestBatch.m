function batch = RunShakeTableFRFTestBatch(N, varargin)
% RunShakeTableFRFTestBatch
%
% Runs one uploaded NAMAZU shaking-table excitation repeatedly while
% measuring the five-sensor rig. Sensor 1 is treated as the base/input
% channel and sensors 2:N as structural response channels.
%
% Each run is saved before FRF analysis begins. The same motor program is
% replayed for all runs to keep the excitation repeatable.

if nargin < 1 || isempty(N)
    N = 5;
end

parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, "MotorPort", "COM4", @(x) ischar(x) || isstring(x));
addParameter(parser, "MotorBaud", 921600, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "SensorPort", "COM5", @(x) ischar(x) || isstring(x));
addParameter(parser, "SensorBaud", 1000000, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "NumSensors", 5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 1 && mod(x, 1) == 0);
addParameter(parser, "SensorSampleRate", 250, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "Direction", "y", @(x) ischar(x) || isstring(x));
addParameter(parser, "AccelerometerRangeG", 8, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);

addParameter(parser, "ExcitationType", "frequency_sweep", ...
    @(x) ischar(x) || isstring(x));
addParameter(parser, "StartFrequencyHz", 0.5, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "EndFrequencyHz", 10, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "DisplacementAmplitudeMm", 0.5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "ExcitationDurationSeconds", 30, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "MotorRateHz", 100, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "RampSeconds", 3, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "ExtraAcquisitionSeconds", 5, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "KanaiTajimiCenterFrequencyHz", 15.14, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "KanaiTajimiDampingRatio", 0.45, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "SpectralComponents", 300, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 10 && mod(x, 1) == 0);
addParameter(parser, "RandomSeed", 1514, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
    x >= 0 && mod(x, 1) == 0 && x <= 2^32-1);
addParameter(parser, "TargetPeakCommandAccelerationG", [], ...
    @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "MaximumCommandDisplacementMm", 0.5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);

addParameter(parser, "OutputRoot", pwd, @(x) ischar(x) || isstring(x));
addParameter(parser, "FolderName", "", @(x) ischar(x) || isstring(x));
addParameter(parser, "FilePrefix", "shake_table_frf_setup", ...
    @(x) ischar(x) || isstring(x));
addParameter(parser, "ExperimentPhase", "setup_calibration", ...
    @(x) ischar(x) || isstring(x));

addParameter(parser, "PromptBeforeUpload", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "PromptBeforeEachRun", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "MakeLivePlot", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "MakeFRFPlots", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "SaveFRFPlots", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "ClosePlotsAfterRun", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "FRFOptions", {}, @(x) iscell(x));
addParameter(parser, "ModeMatchToleranceHz", 0.5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "MinModeOccurrenceFraction", 0.8, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(parser, "MinimumPeakCoherence", 0.6, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
addParameter(parser, "ReferenceFrequenciesHz", [], ...
    @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x > 0)));
addParameter(parser, "ReferenceMatchToleranceHz", 1, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
parse(parser, varargin{:});

validateattributes(N, {'numeric'}, {'scalar', 'integer', 'positive'}, ...
    mfilename, 'N');

settings = parser.Results;
settings.MotorPort = string(settings.MotorPort);
settings.SensorPort = string(settings.SensorPort);
settings.Direction = lower(strtrim(string(settings.Direction)));
settings.ExcitationType = lower(strtrim(string(settings.ExcitationType)));
settings.OutputRoot = string(settings.OutputRoot);
settings.FolderName = string(settings.FolderName);
settings.FilePrefix = string(settings.FilePrefix);
settings.ExperimentPhase = string(settings.ExperimentPhase);
settings.PromptBeforeUpload = logical(settings.PromptBeforeUpload);
settings.PromptBeforeEachRun = logical(settings.PromptBeforeEachRun);
settings.MakeLivePlot = logical(settings.MakeLivePlot);
settings.MakeFRFPlots = logical(settings.MakeFRFPlots);
settings.SaveFRFPlots = logical(settings.SaveFRFPlots);
settings.ClosePlotsAfterRun = logical(settings.ClosePlotsAfterRun);

validateSettings(settings);

%% -------------------- PATHS AND OUTPUT --------------------
functionFolder = fileparts(mfilename("fullpath"));
functionsRoot = fileparts(functionFolder);
matlabRoot = fileparts(functionsRoot);
addpath(genpath(fullfile(matlabRoot, "Methods")));
addpath(genpath(fullfile(matlabRoot, "Functions")));
addpath(genpath(fullfile(matlabRoot, "Classes")));

if strlength(settings.FolderName) == 0
    timestamp = char(datetime("now", "Format", "yyyy-MM-dd_HH-mm-ss"));
    settings.FolderName = sprintf("%s_ShakeTable_FRF_Setup", timestamp);
end

outputFolder = fullfile(settings.OutputRoot, settings.FolderName);

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

%% -------------------- CREATE ONE REPEATABLE EXCITATION --------------------
[positionMm, timeSeconds, signalName, simulationType, generationPSD] = ...
    createExcitation(settings);

simulationTemplate = ShakingData();
simulationTemplate.accelerationSensorsActive = true;
simulationTemplate.numberOfAccSensors = settings.NumSensors;
simulationTemplate.accelerationSensorPort = settings.SensorPort;
simulationTemplate.accelerationSensorBaud = settings.SensorBaud;
simulationTemplate.accelerationSensorSampleRate = settings.SensorSampleRate;
simulationTemplate.inputSignal = [timeSeconds(:), positionMm(:)];
simulationTemplate.motorRate = 1 / median(diff(timeSeconds));
simulationTemplate.simulationType = simulationType;
simulationTemplate.signalGenerator = simulationType;
simulationTemplate.fileName = signalName;

if ~isempty(generationPSD)
    simulationTemplate.psdFunc = generationPSD;
end

simulationTemplate = FilterMotorInput( ...
    simulationTemplate, settings.RampSeconds);
simulationTemplate = simulationTemplate.Setup();

if settings.ExcitationType == "kanai_tajimi"
    simulationTemplate = scaleStochasticCommand( ...
        simulationTemplate, ...
        settings.TargetPeakCommandAccelerationG, ...
        settings.MaximumCommandDisplacementMm);
end

simulationTemplate = WriteMarvCode(simulationTemplate);

nominalPeakAccelerationG = max( ...
    abs(simulationTemplate.inputAcceleration(:, 2)), [], "omitnan") / ...
    (1000 * 9.81);

fprintf("\nNAMAZU shaking-table FRF setup batch\n");
fprintf("  Phase flag:       %s\n", settings.ExperimentPhase);
fprintf("  Runs:             %d\n", N);
fprintf("  Sensor 1:         BASE / FRF input\n");
fprintf("  Sensors 2-%d:      structural responses\n", settings.NumSensors);
fprintf("  Analysis axis:    %s\n", upper(settings.Direction));
fprintf("  Excitation:       %s\n", settings.ExcitationType);
fprintf("  Analysis band:    %.3f to %.3f Hz over %.1f s\n", ...
    settings.StartFrequencyHz, settings.EndFrequencyHz, ...
    settings.ExcitationDurationSeconds);

if settings.ExcitationType == "kanai_tajimi"
    fprintf("  KT center/damping: %.3f Hz / %.3f\n", ...
        settings.KanaiTajimiCenterFrequencyHz, ...
        settings.KanaiTajimiDampingRatio);
    fprintf("  Random seed:      %d\n", settings.RandomSeed);
end

fprintf("  Peak displacement: %.4f mm\n", ...
    max(abs(simulationTemplate.inputSignal(:, 2)), [], "omitnan"));
fprintf("  Command rate:     %.3f Hz\n", simulationTemplate.motorRate);
fprintf("  Nominal peak acc: %.4f g from the discretized command\n", ...
    nominalPeakAccelerationG);
fprintf("  Motor serial:     %s at %d baud\n", ...
    settings.MotorPort, settings.MotorBaud);
fprintf("  Sensor serial:    %s at %d baud\n", ...
    settings.SensorPort, settings.SensorBaud);
fprintf("  Output:           %s\n\n", outputFolder);

fprintf("%s\n\n", [ ...
    'SAFETY: The controller firmware has no active limit-switch protection. ' ...
    'Keep the emergency stop accessible and confirm the carriage can move ' ...
    'through the full commanded displacement.']);

%% -------------------- METADATA AND CHECKPOINT --------------------
batch = struct();
batch.schemaVersion = 1;
batch.experimentType = "shaking_table_frf";
batch.experimentPhase = settings.ExperimentPhase;
batch.isSetupOrCalibration = true;
batch.startedAt = datetime("now", "TimeZone", "local");
batch.completedAt = NaT(1, 1, "TimeZone", "local");
batch.outputFolder = string(outputFolder);
batch.N = N;
batch.settings = settings;
batch.inputSensor = 1;
batch.outputSensors = 2:settings.NumSensors;
batch.nominalPeakCommandAccelerationG = nominalPeakAccelerationG;
batch.excitationTimeSeconds = simulationTemplate.inputSignal(:, 1);
batch.excitationPositionMm = simulationTemplate.inputSignal(:, 2);
batch.files = strings(N, 1);
batch.run = repmat(createEmptyRunSummary(), N, 1);

summaryFile = fullfile(outputFolder, "shake_table_frf_setup_summary.mat");
batch.summaryFile = string(summaryFile);
save(summaryFile, "batch");

%% -------------------- SERIAL CHECK AND MOTOR UPLOAD --------------------
availablePorts = string(serialportlist("available"));

if ~any(strcmpi(availablePorts, settings.MotorPort))
    error("Motor port %s is not available. Available ports: %s", ...
        settings.MotorPort, strjoin(availablePorts, ", "));
end

if ~any(strcmpi(availablePorts, settings.SensorPort))
    error("Sensor port %s is not available. Available ports: %s", ...
        settings.SensorPort, strjoin(availablePorts, ", "));
end

if settings.PromptBeforeUpload
    response = strtrim(input( ...
        'Upload the sweep to the motor controller and continue? y/n [n]: ', 's'));

    if ~strcmpi(response, "y")
        error("RunShakeTableFRFTestBatch:Aborted", "Aborted before motor upload.");
    end
end

motorDevice = serialport(settings.MotorPort, settings.MotorBaud);
motorDevice.Timeout = 10;
motorCleanup = onCleanup(@() cleanupMotorSerial(motorDevice));
pause(0.1);
flush(motorDevice);

fprintf("Uploading one repeatable motion program to the controller...\n");
SendDataToMotor(simulationTemplate, motorDevice);
fprintf("Motion program uploaded. It will be replayed for every run.\n");

%% -------------------- FIVE-RUN ACQUISITION LOOP --------------------
frfCells = cell(N, 1);

frfOptions = settings.FRFOptions;
frfOptions = setNameValueOption(frfOptions, "Direction", settings.Direction);
frfOptions = setNameValueOption(frfOptions, "InputSensor", 1);
frfOptions = setNameValueOption(frfOptions, "OutputSensors", 2:settings.NumSensors);
frfOptions = setNameValueOption(frfOptions, "SampleRate", settings.SensorSampleRate);
frfOptions = setNameValueOption(frfOptions, "NumberOfSensors", settings.NumSensors);
frfOptions = setNameValueOption(frfOptions, "FMin", ...
    max(0.1, settings.StartFrequencyHz));
frfOptions = setNameValueOption(frfOptions, "FMax", settings.EndFrequencyHz);
frfOptions = setNameValueOption(frfOptions, "FrequencyResolutionHz", 0.1);
frfOptions = setNameValueOption(frfOptions, "WindowDurationSeconds", 8);
frfOptions = setNameValueOption(frfOptions, "MinPeakDistanceHz", 1);
frfOptions = setNameValueOption(frfOptions, "DeltaFInterp", 0.5);
frfOptions = setNameValueOption(frfOptions, ...
    "MinimumPeakCoherence", settings.MinimumPeakCoherence);
frfOptions = setNameValueOption(frfOptions, "MakePlots", settings.MakeFRFPlots);

for iRun = 1:N
    fprintf("\nShaking-table FRF setup run %d/%d\n", iRun, N);

    if settings.PromptBeforeEachRun
        prompt = [ ...
            'Confirm the area is clear and the setup is unchanged. ' ...
            'Start this run? y/n [n]: '];
        response = strtrim(input(prompt, 's'));

        if ~strcmpi(response, "y")
            error("RunShakeTableFRFTestBatch:Aborted", ...
                "Batch stopped before run %d. Completed data remain saved.", iRun);
        end
    end

    runStartedAt = datetime("now", "TimeZone", "local");
    currentRunData = simulationTemplate;
    currentRunData = StartExperimentSensorSerial( ...
        currentRunData, motorDevice, ...
        "Direction", settings.Direction, ...
        "PromptBeforeMotion", false, ...
        "MakeLivePlot", settings.MakeLivePlot, ...
        "ClosePlotAfterRun", settings.ClosePlotsAfterRun, ...
        "ExtraAcquisitionSeconds", settings.ExtraAcquisitionSeconds);

    sensorRigData = currentRunData.sensorRigData;
    validationMeanTable = currentRunData.sensorRigValidationMeans;
    T = sensorRigData;

    quality = AssessShakeTableFRFRunQuality(sensorRigData, ...
        "NumSensors", settings.NumSensors, ...
        "Direction", settings.Direction, ...
        "SampleRate", settings.SensorSampleRate, ...
        "ExpectedDurationSeconds", ...
            settings.ExcitationDurationSeconds + settings.ExtraAcquisitionSeconds, ...
        "AccelerometerRangeG", settings.AccelerometerRangeG);

    meta = struct();
    meta.schemaVersion = 1;
    meta.experimentType = "shaking_table_frf";
    meta.experimentPhase = settings.ExperimentPhase;
    meta.isSetupOrCalibration = true;
    meta.runIndex = iRun;
    meta.plannedRuns = N;
    meta.runStartedAt = runStartedAt;
    meta.acquisitionCompletedAt = datetime("now", "TimeZone", "local");
    meta.inputSensor = 1;
    meta.inputSensorRole = "base";
    meta.outputSensors = 2:settings.NumSensors;
    meta.direction = settings.Direction;
    meta.settings = settings;
    meta.quality = quality;
    meta.analysisError = "";
    meta.plotFiles = strings(0, 1);

    runFile = fullfile(outputFolder, sprintf( ...
        "%s_%03d.mat", settings.FilePrefix, iRun));
    currentRunData.fileName = string(runFile);
    frfResults = [];

    % Raw-data checkpoint: if analysis fails, the measurement still exists.
    save(runFile, "T", "sensorRigData", "validationMeanTable", ...
        "currentRunData", "meta", "frfResults");

    figuresBeforeAnalysis = findall(groot, "Type", "figure");

    try
        frfResults = EstimateEigenfrequencyFRF(sensorRigData, frfOptions{:});
        currentRunData.estimatedFrequencies = frfResults.freqHz;
        frfCells{iRun} = frfResults;
    catch ME
        meta.analysisError = string(ME.message);
        warning("RunShakeTableFRFTestBatch:FRFAnalysisFailed", ...
            "FRF analysis failed for run %d: %s", iRun, ME.message);
    end

    newFigures = setdiff( ...
        findall(groot, "Type", "figure"), figuresBeforeAnalysis);

    if settings.SaveFRFPlots && ~isempty(newFigures)
        meta.plotFiles = saveRunFigures(newFigures, outputFolder, iRun);
    end

    if settings.ClosePlotsAfterRun && ~isempty(newFigures)
        close(newFigures);
    end

    meta.completedAt = datetime("now", "TimeZone", "local");
    save(runFile, "T", "sensorRigData", "validationMeanTable", ...
        "currentRunData", "meta", "frfResults");

    batch.files(iRun) = string(runFile);
    batch.run(iRun).index = iRun;
    batch.run(iRun).file = string(runFile);
    batch.run(iRun).completed = true;
    batch.run(iRun).numSamples = height(sensorRigData);
    batch.run(iRun).actualSampleRateHz = quality.actualSampleRateHz;
    batch.run(iRun).baseRMSG = quality.baseRMSG;
    batch.run(iRun).basePeakG = quality.basePeakG;
    batch.run(iRun).maximumRawAbsG = quality.maximumRawAbsG;
    batch.run(iRun).nearClipping = quality.nearClipping;
    batch.run(iRun).hasClipping = quality.hasClipping;
    batch.run(iRun).usableForBatchSummary = quality.usableForBatchSummary;
    batch.run(iRun).qualityMessages = quality.messages;
    batch.run(iRun).qualityWarnings = quality.warnings;
    batch.run(iRun).analysisError = meta.analysisError;

    if ~isempty(frfResults)
        batch.run(iRun).freqHz = frfResults.freqHz;
        batch.run(iRun).zeta = frfResults.zeta;
        batch.run(iRun).minimumPeakCoherence = ...
            frfResults.peakCoherenceMinimum;
    end

    save(summaryFile, "batch");
    fprintf("Saved run %d to %s\n", iRun, runFile);

    if ~quality.usableForBatchSummary
        warning("RunShakeTableFRFTestBatch:RunQualityFailed", ...
            "Run %d will not enter the batch summary: %s", ...
            iRun, strjoin(quality.messages, "; "));
    end
end

%% -------------------- CROSS-RUN MODAL SUMMARY --------------------
qualityUsableRunMask = reshape( ...
    [batch.run.usableForBatchSummary], [], 1);
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

batch.completedAt = datetime("now", "TimeZone", "local");
save(summaryFile, "batch");

fprintf("\nCompleted %d shaking-table setup runs.\n", N);
fprintf("Summary saved to %s\n", summaryFile);

if height(batch.modeInfo) == 0
    fprintf("No repeatable FRF peaks passed the occurrence/coherence settings.\n");
else
    disp(batch.modeInfo);
end

if ~isempty(batch.referenceComparison)
    fprintf("\nComparison with reference frequencies:\n");
    disp(batch.referenceComparison);
end

end

function validateSettings(settings)

if ~ismember(settings.Direction, ["x", "y", "z"])
    error('Direction must be "x", "y", or "z".');
end

if ~ismember(settings.ExcitationType, ["frequency_sweep", "kanai_tajimi"])
    error('ExcitationType must be "frequency_sweep" or "kanai_tajimi".');
end

if strcmpi(settings.MotorPort, settings.SensorPort)
    error("MotorPort and SensorPort must be different serial ports.");
end

if settings.StartFrequencyHz >= settings.EndFrequencyHz
    error("StartFrequencyHz must be lower than EndFrequencyHz.");
end

if settings.EndFrequencyHz >= 0.45 * settings.MotorRateHz
    error([ ...
        'EndFrequencyHz must remain below 45%% of MotorRateHz. ' ...
        'Increase MotorRateHz or lower EndFrequencyHz.']);
end

if settings.EndFrequencyHz >= 0.45 * settings.SensorSampleRate
    error([ ...
        'EndFrequencyHz must remain below 45%% of SensorSampleRate. ' ...
        'Increase SensorSampleRate or lower EndFrequencyHz.']);
end

if 2 * settings.RampSeconds >= settings.ExcitationDurationSeconds
    error("Two RampSeconds intervals must fit inside ExcitationDurationSeconds.");
end

if settings.ExcitationType == "kanai_tajimi"
    if isempty(settings.TargetPeakCommandAccelerationG)
        error("TargetPeakCommandAccelerationG is required for Kanai-Tajimi excitation.");
    end

    if settings.KanaiTajimiCenterFrequencyHz <= settings.StartFrequencyHz || ...
            settings.KanaiTajimiCenterFrequencyHz >= settings.EndFrequencyHz
        error([ ...
            'KanaiTajimiCenterFrequencyHz must lie strictly inside ' ...
            'the StartFrequencyHz-to-EndFrequencyHz band.']);
    end
end

end

function [positionMm, timeSeconds, signalName, simulationType, generationPSD] = ...
    createExcitation(settings)

switch settings.ExcitationType
    case "frequency_sweep"
        frequencyFunction = @(time) 2*pi * sweepFrequencyHz( ...
            time, ...
            settings.StartFrequencyHz, ...
            settings.EndFrequencyHz, ...
            settings.ExcitationDurationSeconds, ...
            settings.RampSeconds);

        [positionMm, timeSeconds, signalName] = SimulateFrequencySweep( ...
            2*pi*settings.EndFrequencyHz, ...
            settings.DisplacementAmplitudeMm, ...
            settings.ExcitationDurationSeconds, ...
            "nStepsPerSecond", settings.MotorRateHz, ...
            "frequencyFunction", frequencyFunction);

        simulationType = MethodEnum.FrequencySweep;
        generationPSD = [];

    case "kanai_tajimi"
        omegaGround = 2*pi*settings.KanaiTajimiCenterFrequencyHz;
        betaGround = settings.KanaiTajimiDampingRatio;
        omegaMinimum = 2*pi*settings.StartFrequencyHz;
        omegaMaximum = 2*pi*settings.EndFrequencyHz;

        accelerationPSD = @(omega) ( ...
            omegaGround^4 + (2*betaGround*omegaGround*omega).^2) ./ ( ...
            (omegaGround^2 - omega.^2).^2 + ...
            (2*betaGround*omegaGround*omega).^2);

        % SimulateShinozuka generates the table displacement. Dividing the
        % desired acceleration PSD by omega^4 gives the corresponding
        % displacement PSD inside the selected, nonzero frequency band.
        generationPSD = @(omega) ...
            double(omega >= omegaMinimum & omega <= omegaMaximum) .* ...
            accelerationPSD(omega) ./ max(omega, omegaMinimum).^4;

        previousRandomState = rng;
        randomStateCleanup = onCleanup(@() rng(previousRandomState));
        rng(settings.RandomSeed, "twister");

        [positionMm, timeSeconds] = SimulateShinozuka( ...
            generationPSD, ...
            settings.ExcitationDurationSeconds, ...
            omegaMaximum, ...
            settings.SpectralComponents, ...
            "nStepsPerSecond", settings.MotorRateHz);

        clear randomStateCleanup;
        positionMm = positionMm - positionMm(1);
        signalName = sprintf("KanaiTajimi_%.3fHz_beta%.3f", ...
            settings.KanaiTajimiCenterFrequencyHz, ...
            settings.KanaiTajimiDampingRatio);
        simulationType = MethodEnum.Shinozuka;
end

end

function simulationData = scaleStochasticCommand( ...
    simulationData, targetPeakAccelerationG, maximumDisplacementMm)

peakAccelerationG = max( ...
    abs(simulationData.inputAcceleration(:, 2)), [], "omitnan") / ...
    (1000 * 9.81);
peakDisplacementMm = max( ...
    abs(simulationData.inputSignal(:, 2)), [], "omitnan");

if ~isfinite(peakAccelerationG) || peakAccelerationG <= 0
    error("Generated stochastic command has no finite acceleration.");
end

if ~isfinite(peakDisplacementMm) || peakDisplacementMm <= 0
    error("Generated stochastic command has no finite displacement.");
end

accelerationScale = targetPeakAccelerationG / peakAccelerationG;
displacementScale = maximumDisplacementMm / peakDisplacementMm;
commandScale = min(accelerationScale, displacementScale);

simulationData.inputSignal(:, 2) = ...
    simulationData.inputSignal(:, 2) * commandScale;
simulationData = simulationData.Setup();

end

function frequencyHz = sweepFrequencyHz( ...
    time, startFrequencyHz, endFrequencyHz, durationSeconds, rampSeconds)

% Hold the band edges during the amplitude ramps. The full-amplitude
% portion therefore sweeps over the complete requested frequency band.
sweepStart = rampSeconds;
sweepEnd = durationSeconds - rampSeconds;
progress = (time - sweepStart) / (sweepEnd - sweepStart);
progress = min(max(progress, 0), 1);
frequencyHz = startFrequencyHz + ...
    (endFrequencyHz - startFrequencyHz) .* progress;

end

function summary = createEmptyRunSummary()

summary = struct( ...
    "index", NaN, ...
    "file", "", ...
    "completed", false, ...
    "numSamples", NaN, ...
    "actualSampleRateHz", NaN, ...
    "baseRMSG", NaN, ...
    "basePeakG", NaN, ...
    "maximumRawAbsG", NaN, ...
    "nearClipping", false, ...
    "hasClipping", false, ...
    "usableForBatchSummary", false, ...
    "qualityMessages", strings(0, 1), ...
    "qualityWarnings", strings(0, 1), ...
    "analysisError", "", ...
    "freqHz", [], ...
    "zeta", [], ...
    "minimumPeakCoherence", []);

end

function options = setNameValueOption(options, name, value)

name = string(name);

if mod(numel(options), 2) ~= 0
    error("FRFOptions must contain complete name-value pairs.");
end

for iOption = 1:2:numel(options)
    if strcmpi(string(options{iOption}), name)
        options{iOption + 1} = value;
        return;
    end
end

options = [options, {char(name), value}];

end

function plotFiles = saveRunFigures(figures, outputFolder, runIndex)

figures = figures(:);
plotFiles = strings(numel(figures), 1);

for iFigure = 1:numel(figures)
    plotFile = fullfile(outputFolder, sprintf( ...
        "shake_table_frf_setup_%03d_plot_%02d.png", ...
        runIndex, iFigure));

    try
        exportgraphics(figures(iFigure), plotFile, "Resolution", 160);
        plotFiles(iFigure) = string(plotFile);
    catch ME
        warning("RunShakeTableFRFTestBatch:PlotSaveFailed", ...
            "Could not save plot %d for run %d: %s", ...
            iFigure, runIndex, ME.message);
    end
end

plotFiles = plotFiles(strlength(plotFiles) > 0);

end

function cleanupMotorSerial(motorDevice)

try
    flush(motorDevice);
catch
end

end
