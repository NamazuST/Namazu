%% Collect one sample with animation
[T, validationMeanTable, meta] = TestSensorRigAnimation("y", "COM9", 1, 30, ...
    "SampleRate", 500, ...
    "Baud", 1000000, ...
    "AnalysisOptions", {"FMax", 100, ...
                        "FrequencyResolutionHz", 0.1, ...
                        "WindowDurationSeconds", 20, ...
                        "MinPeakDistanceHz", 15});

%Check for sampling ratio
fsActual = 1000 / median(diff(T.t_arduino_ms));
disp("Sampling ratio of the signal: " + num2str(fsActual))

%% Run Hammer Test with hardcoded settings, 10 times.
batch = RunHammerTestBatch(100);

%Retrieve output folder name
output_folder_name = batch.outputFolder;

%% Retrieve data summary
batch_summary = AnalyzeHammerTestBatchFFT(output_folder_name);