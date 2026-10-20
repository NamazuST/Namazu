function tests = TestSingleSensorStream
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(mfilename('fullpath')));
testCase.TestData.rate = 1000;
end

function testUSBPacketsCanSplitAnyField(testCase)
[lines, pending] = SensorStreamIntegrity.decodeChunk([], uint8('100;0.0000,0.'));
verifyEmpty(testCase, lines);
[lines, pending] = SensorStreamIntegrity.decodeChunk(pending, ...
    uint8(sprintf('0000,1.0000,1.0000\r')));
verifyEmpty(testCase, lines);
[lines, pending] = SensorStreamIntegrity.decodeChunk(pending, ...
    uint8(sprintf('\n101;nan,nan,nan,nan\r\n102;')));
verifyEqual(testCase, lines, {'100;0.0000,0.0000,1.0000,1.0000'; '101;nan,nan,nan,nan'});
verifyEqual(testCase, pending, uint8('102;'));
end

function testCorruptAndTruncatedRowsAreRejected(testCase)
bad = {['100;0.0000,' char(144) '0.0000,1.0000,1.0000'], ...
    '100;0.0000,0.0000,1.0000', '100;0.0000,NaN,1.0000,1.0000', ...
    '100;0.0000,0.0000,1.0000,1.0000garbage', ...
    '100;0.0000,0.0000,17.0000,17.0000', ...
    '100;0.0000,0.0000,1.0000,0.0000'};
for k = 1:numel(bad)
    [values, kind] = SensorStreamIntegrity.parseSample(bad{k});
    verifyEqual(testCase, kind, "corrupt");
    verifyEmpty(testCase, values);
end
end

function testActualMagnitudeAndFaultMarker(testCase)
[values, kind] = SensorStreamIntegrity.parseSample('100;1.0000,2.0000,2.0000,3.0000');
verifyEqual(testCase, kind, "sample");
verifyEqual(testCase, values, [100 1 2 2 3]);
[~, kind] = SensorStreamIntegrity.parseSample('101;nan,nan,nan,nan');
verifyEqual(testCase, kind, "fault");
end

function testGoodSignalRetainsSamplesForFFT(testCase)
t = (0:0.001:2).'; y = sin(2*pi*12*t);
[actualT, actualY, status] = SensorStreamIntegrity.fftWindow(t, y, 10, 1000, 128);
verifyEqual(testCase, status, "");
verifyEqual(testCase, actualT, t);
verifyEqual(testCase, actualY, y);
end

function testEvenOneMissingSampleWithholdsFFT(testCase)
t = (0:0.001:2).'; y = sin(2*pi*12*t);
t(500) = []; y(500) = [];
[~, ~, status] = SensorStreamIntegrity.fftWindow(t, y, 10, 1000, 128);
verifyTrue(testCase, startsWith(status, "FFT withheld"));
end

function testNanAndDuplicateAreNotSilentlyRemoved(testCase)
t = (0:0.001:2).'; y = sin(2*pi*12*t);
y(500) = NaN;
[~, ~, status] = SensorStreamIntegrity.fftWindow(t, y, 10, 1000, 128);
verifyTrue(testCase, startsWith(status, "FFT withheld"));
y(500) = 0; t(500) = t(499);
[~, ~, status] = SensorStreamIntegrity.fftWindow(t, y, 10, 1000, 128);
verifyTrue(testCase, startsWith(status, "FFT withheld"));
end

function testAgedOutGapAllowsFreshWindow(testCase)
t = (0:0.001:12).'; y = sin(2*pi*12*t);
y(500) = NaN;
[~, ~, status] = SensorStreamIntegrity.fftWindow(t, y, 10, 1000, 128);
verifyEqual(testCase, status, "");
end

function testPlotBreaksInsteadOfDrawingRamps(testCase)
[t, y] = SensorStreamIntegrity.breakPlot([0; .001; 1.2; 1.201], [1; 2; 3; 4], 1000);
verifyEqual(testCase, t, [0; .001; 1.2; 1.2; 1.201]);
verifyEqual(testCase, y([1 2 4 5]), [1; 2; 3; 4]);
verifyTrue(testCase, isnan(y(3)));
end

function testWrongRateIsDetected(testCase)
t = (0:0.002:2).'; y = ones(size(t));
[~, ~, status] = SensorStreamIntegrity.fftWindow(t, y, 10, 1000, 128);
verifyTrue(testCase, startsWith(status, "FFT withheld"));
[~, ~, status] = SensorStreamIntegrity.fftWindow(t, y, 10, 500, 128);
verifyEqual(testCase, status, "");
end

function testUnterminatedBytesAreBounded(testCase)
verifyError(testCase, @() SensorStreamIntegrity.decodeChunk([], repmat(uint8('x'), 1, 4097)), ...
    'SensorStreamIntegrity:UnterminatedLine');
end
