function [time, acceleration, info] = ReadPortoAlegreMeasurement( ...
    folder, measurementIndex)
% ReadPortoAlegreMeasurement
%
% Reads one four-channel Porto Alegre realization from teste_I_R.dat files
% and applies the voltage-to-acceleration calibration from processing.m.

arguments
    folder {mustBeTextScalar}
    measurementIndex (1, 1) double {mustBeInteger, mustBePositive}
end

folder = string(folder);
setPointV = zeros(1, 4);
sensitivityVPerG = [0.1072, 0.1320, 0.1276, 0.1329];
gravity = 9.81;
sensitivityVPerAcceleration = sensitivityVPerG / gravity;

time = [];
voltage = [];

for iChannel = 1:4
    filePath = fullfile(folder, sprintf( ...
        "teste_%d_%d.dat", measurementIndex, iChannel));

    if ~isfile(filePath)
        error("Porto Alegre channel file not found:\n%s", filePath);
    end

    rawText = fileread(filePath);
    rawText = regexprep(rawText, "[()]", "");
    parsed = textscan( ...
        rawText, ...
        "%f%f", ...
        "Delimiter", ",", ...
        "MultipleDelimsAsOne", true, ...
        "CollectOutput", true);
    channelData = parsed{1};

    if size(channelData, 2) ~= 2 || isempty(channelData)
        error("Could not parse Porto Alegre channel file:\n%s", filePath);
    end

    if iChannel == 1
        time = channelData(:, 1);
        voltage = nan(numel(time), 4);
    elseif numel(channelData(:, 1)) ~= numel(time) || ...
            any(abs(channelData(:, 1) - time) > 10 * eps(max(abs(time))))
        error("Porto Alegre channel time vectors are inconsistent.");
    end

    voltage(:, iChannel) = channelData(:, 2); %#ok<AGROW>
end

acceleration = (voltage - setPointV) ./ sensitivityVPerAcceleration;

info = struct();
info.measurementIndex = measurementIndex;
info.folder = folder;
info.setPointV = setPointV;
info.sensitivityVPerG = sensitivityVPerG;
info.sensitivityVPerAcceleration = sensitivityVPerAcceleration;
info.gravity = gravity;
info.numberOfSamples = numel(time);
info.sampleRateHz = 1 / (time(2) - time(1));
info.durationSeconds = time(end) - time(1);

end
