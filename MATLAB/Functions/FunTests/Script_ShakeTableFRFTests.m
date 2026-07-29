%% Script_ShakeTableFRFTests
% Five-run NAMAZU shaking-table FRF setup/calibration batch.
%
% Sensor layout:
%   Sensor 1   = base/table acceleration (FRF input)
%   Sensors 2-5 = response accelerations
%
% This first batch deliberately uses a conservative 0.5-10 Hz sweep.
% Frequencies outside that excited band cannot be identified reliably.

clc;
clearvars;
close all;

%% -------------------- PROJECT PATHS --------------------
scriptPath = mfilename("fullpath");
funTestsFolder = fileparts(scriptPath);
functionsFolder = fileparts(funTestsFolder);
matlabRoot = fileparts(functionsFolder);

addpath(genpath(fullfile(matlabRoot, "Methods")));
addpath(genpath(fullfile(matlabRoot, "Functions")));
addpath(genpath(fullfile(matlabRoot, "Classes")));

outputRoot = fullfile(matlabRoot, "Experiments", ...
    "Shake-Table-FRF-Tests");

%% -------------------- HARDWARE SETTINGS --------------------
numberOfTests = 5;

% Verify these two assignments in Windows Device Manager before running.
motorPort = "COM11";
sensorPort = "COM5";

motorBaud = 921600;
sensorBaud = 1000000;
numberOfSensors = 5;
sensorSampleRateHz = 250;
accelerometerRangeG = 8;

analysisDirection = "y";

%% -------------------- CONSERVATIVE SETUP SWEEP --------------------
startFrequencyHz = 0.5;
endFrequencyHz = 10;
displacementAmplitudeMm = 0.5;
excitationDurationSeconds = 30;
motorCommandRateHz = 100;
rampSeconds = 3;
extraAcquisitionSeconds = 5;

%% -------------------- ANALYSIS AND WORKFLOW --------------------
minimumPeakCoherence = 0.60;
modeMatchToleranceHz = 0.50;
minimumModeOccurrenceFraction = 0.80; % at least 4 of 5 setup runs

makeLivePlot = true;
makeFRFPlots = true;
saveFRFPlots = true;
closePlotsAfterRun = true;

timestamp = char(datetime("now", "Format", "HH-mm-ss"));
folderName = "ST_26_07_29_" + timestamp + ...
    "_Setup_Calibration_5_Runs";

fprintf("\nBefore starting:\n");
fprintf("  1. Sensor 1 must be fixed to the moving base/table.\n");
fprintf("  2. Sensors 2-5 must follow the intended structural measurement order.\n");
fprintf("  3. Cables need enough slack for the complete table travel.\n");
fprintf("  4. Confirm motor=%s and sensor rig=%s.\n", motorPort, sensorPort);
fprintf("  5. Keep the emergency stop accessible.\n\n");

batch = RunShakeTableFRFTestBatch(numberOfTests, ...
    "MotorPort", motorPort, ...
    "MotorBaud", motorBaud, ...
    "SensorPort", sensorPort, ...
    "SensorBaud", sensorBaud, ...
    "NumSensors", numberOfSensors, ...
    "SensorSampleRate", sensorSampleRateHz, ...
    "AccelerometerRangeG", accelerometerRangeG, ...
    "Direction", analysisDirection, ...
    "StartFrequencyHz", startFrequencyHz, ...
    "EndFrequencyHz", endFrequencyHz, ...
    "DisplacementAmplitudeMm", displacementAmplitudeMm, ...
    "ExcitationDurationSeconds", excitationDurationSeconds, ...
    "MotorRateHz", motorCommandRateHz, ...
    "RampSeconds", rampSeconds, ...
    "ExtraAcquisitionSeconds", extraAcquisitionSeconds, ...
    "OutputRoot", outputRoot, ...
    "FolderName", folderName, ...
    "FilePrefix", "ST_FRF_Setup", ...
    "ExperimentPhase", "setup_calibration", ...
    "PromptBeforeUpload", true, ...
    "PromptBeforeEachRun", true, ...
    "MakeLivePlot", makeLivePlot, ...
    "MakeFRFPlots", makeFRFPlots, ...
    "SaveFRFPlots", saveFRFPlots, ...
    "ClosePlotsAfterRun", closePlotsAfterRun, ...
    "MinimumPeakCoherence", minimumPeakCoherence, ...
    "ModeMatchToleranceHz", modeMatchToleranceHz, ...
    "MinModeOccurrenceFraction", minimumModeOccurrenceFraction);

fprintf("\nSetup/calibration batch complete.\n");
fprintf("Data folder: %s\n", batch.outputFolder);
