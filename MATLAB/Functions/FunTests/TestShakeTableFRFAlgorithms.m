function tests = TestShakeTableFRFAlgorithms
% Regression tests for the shaking-table sweep, FRF, mode-shape, and
% acquisition-quality functions. No serial hardware is accessed.

tests = functiontests(localfunctions);

end

function setupOnce(testCase)

testFolder = fileparts(mfilename("fullpath"));
functionsRoot = fileparts(testFolder);
matlabRoot = fileparts(functionsRoot);
addpath(genpath(fullfile(matlabRoot, "Methods")));
addpath(genpath(fullfile(matlabRoot, "Functions")));
addpath(genpath(fullfile(matlabRoot, "Classes")));
testCase.TestData.matlabRoot = matlabRoot;

end

function testFrequencySweepUsesIntegratedPhase(testCase)

[position, time] = SimulateFrequencySweep(2*pi*10, 1, 1, ...
    "nStepsPerSecond", 100);

verifyEqual(testCase, time(1), 0);
verifyEqual(testCase, time(end), 1);
verifyEqual(testCase, numel(time), 101);

[~, halfIndex] = min(abs(time - 0.5));
% Linear omega(t): phase(0.5 s) = 0.5*omegaMax/maxT*t^2 = 2.5*pi.
verifyEqual(testCase, position(halfIndex), 1, "AbsTol", 2e-12);

end

function testFRFFindsModesAndReturnsResponseShapes(testCase)

[T, expectedFrequency] = createSyntheticFRFTable(false);

results = EstimateEigenfrequencyFRF(T, ...
    "Direction", "y", ...
    "InputSensor", 1, ...
    "OutputSensors", 2:5, ...
    "FMin", 1, ...
    "FMax", 10, ...
    "RelativePeakLevel", 0.08, ...
    "MinPeakDistanceHz", 2, ...
    "DeltaFInterp", 0.3, ...
    "FrequencyResolutionHz", 0.05, ...
    "WindowDurationSeconds", 8, ...
    "MinimumPeakCoherence", 0.8, ...
    "MakePlots", false);

verifyEqual(testCase, numel(results.freqHz), numel(expectedFrequency));
verifyEqual(testCase, results.freqHz, expectedFrequency, "AbsTol", 0.2);
verifySize(testCase, results.modeShapeComplexRatio, [5, 2]);
verifySize(testCase, results.modeShapeNormalizedComplex, [5, 2]);
verifyEqual(testCase, results.modeShapeComplexRatio(1, :), [1, 1], ...
    "AbsTol", 10*eps);
verifyEqual(testCase, max(abs(results.modeShapeNormalizedComplex), [], 1), ...
    [1, 1], "AbsTol", 1e-10);
verifyGreaterThan(testCase, min(results.peakCoherenceMinimum), 0.8);

end

function testFRFFallsBackWhenCorrectedColumnsAreInvalid(testCase)

[T, ~] = createSyntheticFRFTable(true);

results = EstimateEigenfrequencyFRF(T, ...
    "Direction", "y", ...
    "FMin", 1, ...
    "FMax", 10, ...
    "MinPeakDistanceHz", 2, ...
    "DeltaFInterp", 0.3, ...
    "MakePlots", false);

verifyEqual(testCase, results.inputVariable, "S1_ay_g");
verifyEqual(testCase, results.outputVariables, ...
    ["S2_ay_g", "S3_ay_g", "S4_ay_g", "S5_ay_g"]);

end

function testShakeTableQualityAcceptsCleanBaseExcitation(testCase)

T = createQualityTable(false);
quality = AssessShakeTableFRFRunQuality(T, ...
    "NumSensors", 5, ...
    "Direction", "y", ...
    "SampleRate", 250, ...
    "ExpectedDurationSeconds", 20, ...
    "AccelerometerRangeG", 8);

verifyTrue(testCase, quality.usableForBatchSummary);
verifyGreaterThan(testCase, quality.baseRMSG, 0.002);
verifyFalse(testCase, quality.hasClipping);
verifyEmpty(testCase, quality.messages);

end

function testShakeTableQualityRejectsClipping(testCase)

T = createQualityTable(true);
quality = AssessShakeTableFRFRunQuality(T, ...
    "NumSensors", 5, ...
    "Direction", "y", ...
    "SampleRate", 250, ...
    "ExpectedDurationSeconds", 20, ...
    "AccelerometerRangeG", 8);

verifyFalse(testCase, quality.usableForBatchSummary);
verifyTrue(testCase, quality.hasClipping);
verifyGreaterThanOrEqual(testCase, quality.maximumRawAbsG, 7.98);

end

function testModalSummaryExcludesQualityFailedRun(testCase)

nRuns = 5;
frfCells = cell(nRuns, 1);

for iRun = 1:nRuns
    frf = struct();
    frf.freqHz = 15.14 + 0.02 * (iRun - 1);
    frf.zeta = 0.01 + 0.0001 * iRun;
    frf.modeShapeNormalizedComplex = [1; 0.8; 0.6; 0.4; 0.2];
    frfCells{iRun} = frf;
end

qualityUsableRunMask = [true; true; true; true; false];
summary = SummarizeShakeTableFRFRuns( ...
    frfCells, qualityUsableRunMask, ...
    "NumSensors", 5, ...
    "ModeMatchToleranceHz", 0.5, ...
    "MinModeOccurrenceFraction", 1.0);

verifyEqual(testCase, summary.numQualityUsableRuns, 4);
verifyEqual(testCase, summary.numIncludedRuns, 4);
verifySize(testCase, summary.freqMatrixHz, [5, 1]);
verifyTrue(testCase, isnan(summary.freqMatrixHz(5, 1)));
verifyEqual(testCase, height(summary.modeInfo), 1);
verifyEqual(testCase, summary.modeInfo.OccurrenceCount, 4);
verifyEqual(testCase, summary.modeInfo.OccurrenceFraction, 1);
verifyEqual(testCase, summary.freqMeanHz, 15.17, "AbsTol", 1e-12);

end

function testEmptyModalSummaryHasConsistentDimensions(testCase)

summary = SummarizeShakeTableFRFRuns( ...
    cell(5, 1), true(5, 1), ...
    "NumSensors", 5);

verifyEqual(testCase, summary.numIncludedRuns, 0);
verifySize(testCase, summary.freqMatrixHz, [5, 0]);
verifySize(testCase, summary.freqMeanHz, [1, 0]);
verifySize(testCase, summary.zetaMean, [1, 0]);
verifyEqual(testCase, height(summary.modeInfo), 0);
verifySize(testCase, summary.modeShapeMeanNormalizedComplex, [5, 0]);

end

function [T, expectedFrequency] = createSyntheticFRFTable(invalidCorrected)

fs = 250;
durationSeconds = 40;
t = (0:1/fs:durationSeconds-1/fs).';
rng(14);
inputSignal = 0.04 * randn(size(t));
expectedFrequency = [3, 7];
radii = [0.985, 0.98];
modalCoefficient = [
     1.0, -0.3;
     0.8,  0.5;
    -0.6,  1.0;
    -0.4, -0.7
];

outputs = zeros(numel(t), 4);

for iMode = 1:numel(expectedFrequency)
    denominator = [ ...
        1, ...
        -2*radii(iMode)*cos(2*pi*expectedFrequency(iMode)/fs), ...
        radii(iMode)^2 ...
    ];
    modalResponse = filter(1-radii(iMode), denominator, inputSignal);

    for iOutput = 1:4
        outputs(:, iOutput) = outputs(:, iOutput) + ...
            modalCoefficient(iOutput, iMode) * modalResponse;
    end
end

T = table(t, 'VariableNames', {'t_arduino_elapsed_s'});
T.S1_ay_g = inputSignal;

for iSensor = 2:5
    T.(sprintf("S%d_ay_g", iSensor)) = outputs(:, iSensor-1);
end

for iSensor = 1:5
    rawName = sprintf("S%d_ay_g", iSensor);
    correctedName = sprintf("S%d_ay_g_corr", iSensor);

    if invalidCorrected
        T.(correctedName) = nan(height(T), 1);
    else
        T.(correctedName) = T.(rawName);
    end
end

T.Properties.UserData = struct( ...
    "sampleRate", fs, ...
    "numberOfSensors", 5);

end

function T = createQualityTable(includeClipping)

fs = 250;
t = (0:1/fs:20-1/fs).';
base = 0.05 * sin(2*pi*3*t);
T = table(t, 'VariableNames', {'t_arduino_elapsed_s'});

for iSensor = 1:5
    for axis = ["x", "y", "z"]
        rawName = sprintf("S%d_a%s_g", iSensor, axis);

        if axis == "y"
            values = (1 + 0.1*iSensor) * base;
        else
            values = zeros(size(t));
        end

        T.(rawName) = values;
        T.(rawName + "_corr") = values;
    end
end

if includeClipping
    T.S4_ay_g(100) = 7.99;
    T.S4_ay_g_corr(100) = 7.99;
end

T.Properties.UserData = struct( ...
    "sampleRate", fs, ...
    "numberOfSensors", 5);

end
