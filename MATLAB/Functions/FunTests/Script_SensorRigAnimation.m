% Collect one sample with animation.
%
% The ESP32 sensor-rig firmware currently streams at 250 Hz. Keep this value
% aligned with SAMPLE_RATE_HZ in Sensors/sensor_rig_esp32/src/main.cpp.
sampleRateHz = 250;
numSensors = 5;
direction = "y";
fMaxHz = 100;
fftSignalMode = "raw"; % "raw" or "corrected"
plotUpdateRateHz = 30; % Display only; data are still acquired at sampleRateHz.

[T, validationMeanTable, meta] = TestSensorRigAnimation(direction, "COM10", numSensors, 60, ...
    "SampleRate", sampleRateHz, ...
    "PlotUpdateRateHz", plotUpdateRateHz, ...
    "Baud", 1000000, ...
    "RunAnalysis", false);

% Check sample timing and finite channel counts before running FFT.
if height(T) < 2
    error("Sensor animation recorded too few samples.");
end

fsActual = 1000 / median(diff(T.t_arduino_ms));
fprintf("Actual sample rate from ESP32 timestamps: %.3f Hz\n", fsActual);

validSensors = [];
useCorrectedSignalsForFFT = strcmpi(fftSignalMode, "corrected");
fprintf("Finite %s-axis samples per sensor:\n", direction);

for iSens = 1:numSensors
    rawName = sprintf("S%d_a%s_g", iSens, direction);
    corrName = sprintf("S%d_a%s_g_corr", iSens, direction);

    rawCount = countFiniteSamples(T, rawName);
    corrCount = countFiniteSamples(T, corrName);

    fprintf("  S%d raw=%d corrected=%d\n", iSens, rawCount, corrCount);

    countsByMode = [rawCount, corrCount];
    analysisCount = countsByMode(1 + double(useCorrectedSignalsForFFT));

    if analysisCount >= 64
        validSensors(end + 1) = iSens; %#ok<SAGROW>
    end
end

if isempty(validSensors)
    error("No sensor has enough finite %s-axis samples for FFT.", direction);
end

fftResults = EstimateEigenfrequencyFFT(T, ...
    "Direction", direction, ...
    "UseCorrectedSignals", useCorrectedSignalsForFFT, ...
    "SampleRate", sampleRateHz, ...
    "Sensors", validSensors, ...
    "FMax", fMaxHz, ...
    "FrequencyResolutionHz", 0.1, ...
    "MinPeakDistanceHz", 15);

function n = countFiniteSamples(T, varName)

if ismember(varName, string(T.Properties.VariableNames))
    n = nnz(isfinite(T.(varName)));
else
    n = 0;
end

end
