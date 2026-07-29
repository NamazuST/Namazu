%% Prepare HT_26_06_21 hammer-test campaign with ESP32 sensor rig
%
% Purpose:
%   1. Verify the 5-sensor ESP32 rig with a quiet steady-state baseline.
%   2. Quantify residual bias/noise after the firmware startup validation.
%   3. Save one campaign settings MAT-file for reproducibility.
%   4. Optionally run a small hammer-test batch and FFT analysis.
%
% Notes:
%   - Idle/baseline FFT peaks are a noise fingerprint, not modal estimates.
%   - The quiet baseline defines campaign correction offsets. This avoids
%     depending on whether MATLAB saw the ESP32 startup validation text.
%   - EstimateEigenfrequencyFFT mean-centers every channel before the FFT.

clear;
clc;

%% -------------------- PATH SETUP --------------------
scriptFolder = fileparts(mfilename("fullpath"));
functionsRoot = fileparts(scriptFolder);
matlabRoot = fileparts(functionsRoot);

addpath(genpath(fullfile(matlabRoot, "Functions")));
addpath(genpath(fullfile(matlabRoot, "Classes")));

%% -------------------- CAMPAIGN SETTINGS --------------------
campaignId = "HT_26_06_21_Hammer_Test";
campaignTimestamp = string(datetime("now", "Format", "yyyy-MM-dd-HH-mm-ss"));
campaignFolderName = campaignId + "_" + campaignTimestamp;

port = "COM5";             % Change if Windows assigns a different ESP32 port.
baud = 1000000;
numSensors = 5;
sampleRateHz = 250;        % ESP32 firmware SAMPLE_RATE_HZ.
direction = "y";

baselineDurationSeconds = 30;
hammerDurationSeconds = 12;
numHammerRuns = 5;         % Small test batch. Increase later for the campaign.

runBaseline = true;
runBatchAnalysis = true;

fMaxHz = 90;               % Below the 94 Hz MPU6050 DLPF bandwidth.
frequencyResolutionHz = 0.1;
minPeakDistanceHz = 10;
relativePeakLevel = 0.03;
modeMatchToleranceHz = 3;
minModeOccurrenceFraction = 0.5;

outputRoot = fullfile(matlabRoot, "Experiments", "Hammer-Test");
campaignFolder = fullfile(outputRoot, campaignFolderName);

if ~isfolder(campaignFolder)
    mkdir(campaignFolder);
end

fftOptions = { ...
    "Direction", direction, ...
    "SampleRate", sampleRateHz, ...
    "Sensors", 1:numSensors, ...
    "FMax", fMaxHz, ...
    "FrequencyResolutionHz", frequencyResolutionHz, ...
    "RelativePeakLevel", relativePeakLevel, ...
    "MinPeakDistanceHz", minPeakDistanceHz, ...
    "MakePlots", false};

firmwareSettings = struct();
firmwareSettings.name = "ESP32 MPU6050 Multi-Sensor CSV Acceleration Rig";
firmwareSettings.numSensors = numSensors;
firmwareSettings.sampleRateHz = sampleRateHz;
firmwareSettings.serialBaud = baud;
firmwareSettings.i2cClockHz = 400000;
firmwareSettings.i2cSdaPin = 21;
firmwareSettings.i2cSclPin = 22;
firmwareSettings.ad0Pins = [13, 14, 25, 26, 27];
firmwareSettings.accelerometerRangeG = 8;
firmwareSettings.accelerometerScaleLsbPerG = 4096;
firmwareSettings.mpuAccelConfig = "0x10";
firmwareSettings.mpuDlpfConfig = 2;
firmwareSettings.mpuSampleRateDivider = 3;
firmwareSettings.printMagnitude = true;
firmwareSettings.settingsFile = ...
    fullfile(fileparts(matlabRoot), "Sensors", "sensor_rig_esp32", "FIRMWARE_SETTINGS.md");

campaign = struct();
campaign.id = campaignId;
campaign.createdAt = datetime("now", "TimeZone", "local");
campaign.folder = string(campaignFolder);
campaign.port = port;
campaign.baud = baud;
campaign.numSensors = numSensors;
campaign.sampleRateHz = sampleRateHz;
campaign.direction = direction;
campaign.baselineDurationSeconds = baselineDurationSeconds;
campaign.hammerDurationSeconds = hammerDurationSeconds;
campaign.numHammerRuns = numHammerRuns;
campaign.fftOptions = fftOptions;
campaign.modeMatchToleranceHz = modeMatchToleranceHz;
campaign.minModeOccurrenceFraction = minModeOccurrenceFraction;
campaign.firmwareSettings = firmwareSettings;

campaignSettingsFile = fullfile(campaignFolder, "campaign_preflight_settings.mat");
save(campaignSettingsFile, "campaign");

fprintf("Campaign preflight folder:\n  %s\n", campaignFolder);
fprintf("Saved campaign settings to:\n  %s\n\n", campaignSettingsFile);

%% -------------------- QUIET BASELINE --------------------
figuresBeforePreflight = findall(groot, "Type", "figure");

if runBaseline
    baselineFFTResults = [];

    fprintf("Recording quiet baseline for %.1f s. Keep the full rig still.\n", ...
        baselineDurationSeconds);

    [baselineData, baselineValidationMeans, baselineMeta] = TestSensorRigAnimation( ...
        direction, ...
        port, ...
        numSensors, ...
        baselineDurationSeconds, ...
        "SampleRate", sampleRateHz, ...
        "Baud", baud, ...
        "UseCorrectedData", false, ...
        "SaveData", false, ...
        "OutputFolder", campaignFolder, ...
        "RunAnalysis", false);

    baselineCorrectionMeans = computeBaselineCorrectionMeans(baselineData, numSensors);

    if any(~isfinite(baselineCorrectionMeans(:, 1:3)), "all")
        error("Baseline correction offsets could not be computed for all sensor axes.");
    end

    baselineCorrectionTable = createCorrectionMeanTable(baselineCorrectionMeans, numSensors);
    baselineData = addBaselineCorrectedColumns(baselineData, baselineCorrectionMeans, numSensors);

    baselineStats = summarizeBaseline(baselineData, numSensors);
    baselineStatsFile = fullfile(campaignFolder, "baseline_noise_bias_summary.csv");
    writetable(baselineStats, baselineStatsFile);
    baselineCorrectionFile = fullfile(campaignFolder, "baseline_correction_offsets.csv");
    writetable(baselineCorrectionTable, baselineCorrectionFile);

    fprintf("\nBaseline residual noise/bias summary:\n");
    disp(baselineStats);
    fprintf("Saved baseline summary to:\n  %s\n", baselineStatsFile);
    fprintf("Saved baseline correction offsets to:\n  %s\n", baselineCorrectionFile);

    try
        useCorrectedFFT = hasUsableCorrectedChannels(baselineData, numSensors, direction);

        if ~useCorrectedFFT
            warning("BaselineFFT:NoCorrectedChannels", ...
                "Corrected baseline channels are missing or NaN. FFT uses raw, mean-centered channels.");
        end

        baselineFFTResults = EstimateEigenfrequencyFFT( ...
            baselineData, ...
            fftOptions{:}, ...
            "UseCorrectedSignals", useCorrectedFFT, ...
            "MakePlots", true);

        fprintf("\nBaseline FFT noise/crosstalk peaks, not modal estimates:\n");
        printPeakSummary(baselineFFTResults);
    catch ME
        warning("BaselineFFT:Failed", "Baseline FFT analysis failed: %s", ME.message);
    end

    baselineFile = fullfile(campaignFolder, "baseline_preflight.mat");
    save(baselineFile, ...
        "baselineData", ...
        "baselineValidationMeans", ...
        "baselineCorrectionMeans", ...
        "baselineCorrectionTable", ...
        "baselineMeta", ...
        "baselineStats", ...
        "baselineFFTResults");
    fprintf("Saved baseline preflight data to:\n  %s\n\n", baselineFile);
end

if ~exist("baselineCorrectionMeans", "var")
    baselineCorrectionMeans = [];
end

%% -------------------- OPTIONAL HAMMER TEST BATCH --------------------
hammerBatch = [];
batchSummary = [];

runHammerBatchAnswer = input("Start a small hammer-test batch now? y/n [n]: ", "s");
runHammerBatch = strcmpi(strtrim(runHammerBatchAnswer), "y");

if runHammerBatch
    preflightFigures = findNewFigures(figuresBeforePreflight);
    closeFiguresSafely(preflightFigures);

    fprintf("Starting hammer-test batch with %d runs.\n", numHammerRuns);

    hammerBatch = RunHammerTestBatch( ...
        numHammerRuns, ...
        "Port", port, ...
        "Baud", baud, ...
        "NumSensors", numSensors, ...
        "SampleRate", sampleRateHz, ...
        "DurationSeconds", hammerDurationSeconds, ...
        "Direction", direction, ...
        "UseCorrectedData", true, ...
        "AccelerometerRangeG", firmwareSettings.accelerometerRangeG, ...
        "OutputRoot", outputRoot, ...
        "FolderName", campaignFolderName, ...
        "FilePrefix", "hammer_test", ...
        "RunFFTAnalysis", false, ...
        "FFTOptions", fftOptions, ...
        "CorrectionMeans", baselineCorrectionMeans, ...
        "PromptBeforeEachRun", true, ...
        "CountdownSeconds", 3, ...
        "MakeLivePlot", true, ...
        "ModeMatchToleranceHz", modeMatchToleranceHz, ...
        "MinModeOccurrenceFraction", minModeOccurrenceFraction);

    if runBatchAnalysis
        batchSummary = AnalyzeHammerTestBatchFFT( ...
            hammerBatch.outputFolder, ...
            "FFTOptions", fftOptions, ...
            "NumMeasurementModes", 6, ...
            "ModeMatchToleranceHz", modeMatchToleranceHz, ...
            "MinModeOccurrenceFraction", minModeOccurrenceFraction);
    end

    hammerBatchFile = fullfile(campaignFolder, "hammer_batch_preflight.mat");
    save(hammerBatchFile, "hammerBatch", "batchSummary");
    fprintf("Saved hammer batch preflight data to:\n  %s\n", hammerBatchFile);
else
    fprintf("Hammer batch not started. Review the baseline first.\n");
    fprintf("To run a small hammer batch, rerun this script and answer y at the prompt.\n");
end

%% ========================================================================
% LOCAL HELPER FUNCTIONS
% ========================================================================

function correctionMeans = computeBaselineCorrectionMeans(T, numSensors)

axisCodes = ["ax", "ay", "az"];
correctionMeans = nan(numSensors, 4);

for iSens = 1:numSensors
    for iAxis = 1:numel(axisCodes)
        rawName = sprintf("S%d_%s_g", iSens, axisCodes(iAxis));

        if ismember(rawName, T.Properties.VariableNames)
            correctionMeans(iSens, iAxis) = mean(T.(rawName), "omitnan");
        end
    end

    magName = sprintf("S%d_mag_g", iSens);

    if ismember(magName, T.Properties.VariableNames)
        correctionMeans(iSens, 4) = mean(T.(magName), "omitnan");
    elseif all(isfinite(correctionMeans(iSens, 1:3)))
        correctionMeans(iSens, 4) = norm(correctionMeans(iSens, 1:3));
    end
end

end

function correctionTable = createCorrectionMeanTable(correctionMeans, numSensors)

correctionTable = array2table(correctionMeans, ...
    "VariableNames", ["Mean_ax_g", "Mean_ay_g", "Mean_az_g", "Mean_mag_g"]);
correctionTable.Sensor = (1:numSensors).';
correctionTable = movevars(correctionTable, "Sensor", "Before", 1);

end

function T = addBaselineCorrectedColumns(T, correctionMeans, numSensors)

axisNames = ["ax_g", "ay_g", "az_g"];

for iSens = 1:numSensors
    for iAxis = 1:numel(axisNames)
        rawName = sprintf("S%d_%s", iSens, axisNames(iAxis));
        corrName = sprintf("S%d_%s_corr", iSens, axisNames(iAxis));
        offset = correctionMeans(iSens, iAxis);

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

function stats = summarizeBaseline(T, numSensors)

axisCodes = ["ax", "ay", "az", "mag"];
axisLabels = ["x", "y", "z", "mag"];

nRows = numSensors * numel(axisCodes);
Sensor = nan(nRows, 1);
Axis = strings(nRows, 1);
RawMeanG = nan(nRows, 1);
RawStdG = nan(nRows, 1);
RawRMSG = nan(nRows, 1);
RawPeakToPeakG = nan(nRows, 1);
CorrectedMeanG = nan(nRows, 1);
CorrectedStdG = nan(nRows, 1);
CorrectedRMSG = nan(nRows, 1);
CorrectedPeakToPeakG = nan(nRows, 1);

iRow = 0;

for iSens = 1:numSensors
    for iAxis = 1:numel(axisCodes)
        iRow = iRow + 1;

        Sensor(iRow) = iSens;
        Axis(iRow) = axisLabels(iAxis);

        rawName = sprintf("S%d_%s_g", iSens, axisCodes(iAxis));
        corrName = sprintf("S%d_%s_g_corr", iSens, axisCodes(iAxis));

        if ismember(rawName, T.Properties.VariableNames)
            raw = T.(rawName);
            RawMeanG(iRow) = mean(raw, "omitnan");
            RawStdG(iRow) = std(raw, 0, "omitnan");
            RawRMSG(iRow) = sqrt(mean(raw.^2, "omitnan"));
            RawPeakToPeakG(iRow) = max(raw, [], "omitnan") - min(raw, [], "omitnan");
        end

        if ismember(corrName, T.Properties.VariableNames)
            corrected = T.(corrName);
            CorrectedMeanG(iRow) = mean(corrected, "omitnan");
            CorrectedStdG(iRow) = std(corrected, 0, "omitnan");
            CorrectedRMSG(iRow) = sqrt(mean(corrected.^2, "omitnan"));
            CorrectedPeakToPeakG(iRow) = ...
                max(corrected, [], "omitnan") - min(corrected, [], "omitnan");
        end
    end
end

stats = table( ...
    Sensor, ...
    Axis, ...
    RawMeanG, ...
    RawStdG, ...
    RawRMSG, ...
    RawPeakToPeakG, ...
    CorrectedMeanG, ...
    CorrectedStdG, ...
    CorrectedRMSG, ...
    CorrectedPeakToPeakG);

end

function isUsable = hasUsableCorrectedChannels(T, numSensors, direction)

direction = char(lower(strtrim(string(direction))));
isUsable = true;

for iSens = 1:numSensors
    if strcmp(direction, "mag")
        varName = sprintf("S%d_mag_g_corr", iSens);
    else
        varName = sprintf("S%d_a%s_g_corr", iSens, direction);
    end

    if ~ismember(varName, T.Properties.VariableNames) || ...
            ~any(isfinite(T.(varName)))
        isUsable = false;
        return;
    end
end

end

function printPeakSummary(results)

if isempty(results) || ~isfield(results, "freqHz") || isempty(results.freqHz)
    fprintf("  No peaks found.\n");
    return;
end

for iPeak = 1:numel(results.freqHz)
    fprintf("  Peak %2d: f = %10.5f Hz, sensor = %d\n", ...
        iPeak, results.freqHz(iPeak), results.peakSensor(iPeak));
end

end

function closeFiguresSafely(figures)

figures = figures(isgraphics(figures, "figure"));

if ~isempty(figures)
    close(figures);
end

end

function figures = findNewFigures(previousFigures)

figures = findall(groot, "Type", "figure");
previousFigures = previousFigures(isgraphics(previousFigures, "figure"));
keep = true(size(figures));

for iFigure = 1:numel(figures)
    keep(iFigure) = ~any(figures(iFigure) == previousFigures);
end

figures = figures(keep);

end
