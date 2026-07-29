function tests = TestHammerTestAlgorithms
% Regression tests for the hammer-test quality and modal-analysis pipeline.

tests = functiontests(localfunctions);

end

function setupOnce(testCase)

testFolder = fileparts(mfilename("fullpath"));
functionsRoot = fileparts(testFolder);
addpath(genpath(functionsRoot));
testCase.TestData.functionsRoot = functionsRoot;

end

function testKnownModalFrequenciesAndDamping(testCase)

[T, expectedFrequency, expectedZeta] = createSyntheticHammerTable();

results = EstimateEigenfrequencyFFT(T, ...
    "Direction", "y", ...
    "Sensors", 1:5, ...
    "FMax", 90, ...
    "FrequencyResolutionHz", 0.1, ...
    "RelativePeakLevel", 0.03, ...
    "MinPeakDistanceHz", 10, ...
    "MakePlots", false);

verifyEqual(testCase, numel(results.freqHz), numel(expectedFrequency));
verifyEqual(testCase, results.freqHz, expectedFrequency, "AbsTol", 0.05);
verifyEqual(testCase, results.zeta, expectedZeta, "AbsTol", 7e-4);
verifyEqual(testCase, results.dampingFitStatus, repmat("accepted", 1, 3));

end

function testRefinedPeaksStayInsideSearchRange(testCase)

fs = 250;
t = (0:1/fs:12-1/fs).';
signal = sin(2*pi*102*t);
T = table(t, signal, ...
    'VariableNames', {'t_arduino_elapsed_s', 'S1_ay_g_corr'});
T.Properties.UserData = struct("sampleRate", fs, "numberOfSensors", 1);

analysis = @() EstimateEigenfrequencyFFT(T, ...
    "Direction", "y", ...
    "Sensors", 1, ...
    "FMin", 0.5, ...
    "FMax", 90, ...
    "FrequencyResolutionHz", 0.1, ...
    "RelativePeakLevel", 0.01, ...
    "MinPeakDistanceHz", 10, ...
    "MakePlots", false);

verifyError(testCase, analysis, ...
    "EstimateEigenfrequencyFFT:EnergyOutsideSearchRange");

end

function testNonDecayingDampingFitIsRejected(testCase)

fs = 250;
t = (0:1/fs:12-1/fs).';
tau = max(t - 1, 0);
signal = double(t >= 1) .* exp(0.15*tau) .* sin(2*pi*15*tau);
T = table(t, signal, ...
    'VariableNames', {'t_arduino_elapsed_s', 'S1_ay_g_corr'});
T.Properties.UserData = struct("sampleRate", fs, "numberOfSensors", 1);

results = EstimateEigenfrequencyFFT(T, ...
    "Direction", "y", ...
    "Sensors", 1, ...
    "FMax", 90, ...
    "FrequencyResolutionHz", 0.1, ...
    "RelativePeakLevel", 0.2, ...
    "MinPeakDistanceHz", 10, ...
    "MakePlots", false);

verifyTrue(testCase, all(isnan(results.zeta)));
verifyFalse(testCase, any(results.dampingFitStatus == "accepted"));

end

function testModeMatchingUsesFrequencyAndOccurrence(testCase)

frequencyCells = { ...
    [15.0, 44.0, 73.0, 88.0], ...
    [15.1, 43.9, 73.2, 88.1], ...
    [14.9, 44.2, 72.9], ...
    [15.2, 44.1, 73.1, 87.8, 82.0]};
zetaCells = { ...
    [0.010, 0.020, 0.030, 0.040], ...
    [0.011, 0.021, 0.031, 0.041], ...
    [0.009, 0.019, 0.029], ...
    [0.012, 0.022, 0.032, 0.042, 0.5]};

[frequencyMatrix, zetaMatrix, modeInfo] = MatchModalPeaksAcrossRuns( ...
    frequencyCells, ...
    zetaCells, ...
    "ToleranceHz", 3, ...
    "MinOccurrenceFraction", 0.5);

verifySize(testCase, frequencyMatrix, [4, 4]);
verifySize(testCase, zetaMatrix, [4, 4]);
verifyEqual(testCase, modeInfo.CenterHz, [15.05; 44.05; 73.05; 88.0], ...
    "AbsTol", 0.05);
verifyEqual(testCase, modeInfo.OccurrenceCount, [4; 4; 4; 3]);
verifyTrue(testCase, isnan(frequencyMatrix(3, 4)));
verifyFalse(testCase, any(abs(modeInfo.CenterHz - 82) < 1));

end

function testQualityGateAcceptsCleanImpact(testCase)

[T, ~, ~] = createSyntheticHammerTable();
quality = AssessHammerRunQuality(T, ...
    "NumSensors", 5, ...
    "Direction", "y", ...
    "SampleRate", 250, ...
    "DurationSeconds", 12);

verifyTrue(testCase, quality.usableForAnalysis);
verifyTrue(testCase, quality.impactDetected);
verifyEqual(testCase, quality.estimatedMissingSamples, 0);
verifyEmpty(testCase, quality.messages);

end

function testQualityGateRejectsTimestampGap(testCase)

[T, ~, ~] = createSyntheticHammerTable();
T(100:105, :) = [];
quality = AssessHammerRunQuality(T, ...
    "NumSensors", 5, ...
    "Direction", "y", ...
    "SampleRate", 250, ...
    "DurationSeconds", 12);

verifyFalse(testCase, quality.usableForAnalysis);
verifyGreaterThan(testCase, quality.largeGapCount, 0);

end

function testQualityGateRejectsNoImpactAndClipping(testCase)

fs = 250;
t = (0:1/fs:12-1/fs).';
T = table(t, zeros(size(t)), ...
    'VariableNames', {'t_arduino_elapsed_s', 'S1_ay_g_corr'});

qualityNoImpact = AssessHammerRunQuality(T, ...
    "NumSensors", 1, ...
    "Direction", "y", ...
    "SampleRate", fs, ...
    "DurationSeconds", 12);

verifyFalse(testCase, qualityNoImpact.usableForAnalysis);
verifyFalse(testCase, qualityNoImpact.impactDetected);

[TImpact, ~, ~] = createSyntheticHammerTable();
qualityClipped = AssessHammerRunQuality(TImpact, ...
    "NumSensors", 5, ...
    "Direction", "y", ...
    "SampleRate", fs, ...
    "DurationSeconds", 12, ...
    "Clipping", struct("hasClipping", true));

verifyFalse(testCase, qualityClipped.usableForAnalysis);
verifyTrue(testCase, qualityClipped.hasClipping);

end

function testTimeHistoryPeakStoresRawAndCorrectedMaximum(testCase)

t = [0; 0.1; 0.2; 0.3];
sensor1Raw = [0; 5; 0; 0];
sensor1Corrected = [0; 3; 0; 0];
sensor2Raw = [0; 0; -4.5; 0];
sensor2Corrected = [0; 0; -4; 0];
T = table( ...
    t, ...
    sensor1Raw, ...
    sensor1Corrected, ...
    sensor2Raw, ...
    sensor2Corrected, ...
    'VariableNames', { ...
    't_arduino_elapsed_s', ...
    'S1_ay_g', ...
    'S1_ay_g_corr', ...
    'S2_ay_g', ...
    'S2_ay_g_corr'});

peak = SummarizeHammerTimeHistoryPeak(T, ...
    "NumSensors", 2, "Direction", "y");

verifyEqual(testCase, peak.rawMaxAbsG, 5);
verifyEqual(testCase, peak.correctedMaxAbsG, 4);
verifyEqual(testCase, peak.maxAbsG, 4);
verifyEqual(testCase, peak.signedPeakG, -4);
verifyEqual(testCase, peak.peakSensor, 2);
verifyEqual(testCase, peak.peakTimeSeconds, 0.2, "AbsTol", eps);
verifyEqual(testCase, peak.selectedSource, "corrected");

end

function [T, expectedFrequency, expectedZeta] = createSyntheticHammerTable()

fs = 250;
t = (0:1/fs:12-1/fs).';
tau = max(t - 1, 0);
gate = double(t >= 1);
frequency = [15, 44, 73];
lambda = [0.45, 0.65, 0.80];
amplitude = [1.0, 0.7, 0.5];
signal = zeros(size(t));

for iMode = 1:numel(frequency)
    signal = signal + gate .* amplitude(iMode) .* exp(-lambda(iMode)*tau) .* ...
        sin(2*pi*frequency(iMode)*tau);
end

T = table(t, 'VariableNames', {'t_arduino_elapsed_s'});

for iSensor = 1:5
    T.(sprintf("S%d_ay_g_corr", iSensor)) = signal * (1 + 0.05*iSensor);
end

T.Properties.UserData = struct("sampleRate", fs, "numberOfSensors", 5);
expectedFrequency = frequency;
expectedZeta = lambda ./ (2*pi*frequency);

end
