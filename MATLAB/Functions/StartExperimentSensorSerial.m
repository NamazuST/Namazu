function [currentSimulationData] = StartExperimentSensorSerial(currentSimulationData,dev)

% StartExperiment
% Sensor-active branch uses a serial CSV stream from the MPU6050 sensor rig.
% Expected Arduino line format:
%
%   t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g;S2_ax_g,...
%
% The function keeps compatibility fields:
%   currentSimulationData.dataPlate
%   currentSimulationData.dataObject
%   currentSimulationData.sampleRate
%
% Full multi-sensor data are stored in:
%   currentSimulationData.sensorRigData
%   currentSimulationData.sensorRigValidationMeans

% Are sensors connected or not?
if currentSimulationData.accelerationSensorsActive == true

    %% -------------------- SENSOR RIG SETTINGS --------------------
    port       = currentSimulationData.accelerationSensorPort;
    baud       = currentSimulationData.accelerationSensorBaud;
    NumSens    = currentSimulationData.numberOfAccSensors;
    sampleRate = currentSimulationData.accelerationSensorSampleRate;

    NumValsPerSens = 4;                          % ax_g, ay_g, az_g, mag_g
    NumValsTotal   = 1 + NumSens*NumValsPerSens; % +1 for t_ms

    % Check for sensor Arduino port
    portList = serialportlist("available");

    if ~any(strcmp(string(portList), string(port)))
        error('Sensor port not found/open or port is in use. Check USB connection!')
    end

    fprintf('Opening sensor rig serial port %s at %d baud...\n', string(port), baud);

    s = serialport(port, baud);
    configureTerminator(s, "CR/LF");
    s.Timeout = 5;

    cleanupObj = onCleanup(@() cleanupSensorSerial(s));

    % Clear stale bytes already sitting in the buffer.
    flush(s);

    % Give Arduino time to restart after opening serial port.
    pause(2);

    %% -------------------- PLOT SETUP --------------------
    figure;

    p1 = subplot(2,1,1);
    xlabel('t [s]');
    ylabel('Acceleration [g]');
    title('Acceleration values from MPU6050 sensor 1');
    x1_val = animatedline('Color',[0 0.4470 0.7410]);
    y1_val = animatedline('Color',[0.8500 0.3250 0.0980]);
    z1_val = animatedline('Color',[0.9290 0.6940 0.1250]);
    axis tight;
    legend('X','Y','Z');

    p2 = subplot(2,1,2);
    xlabel('t [s]');
    ylabel('Acceleration x [g]');
    title('X-axis acceleration of all MPU6050 sensors');
    hold on;
    colors = lines(NumSens);
    xSensorLines = gobjects(NumSens,1);

    for iSens = 1:NumSens
        xSensorLines(iSens) = animatedline( ...
            'Color', colors(iSens,:), ...
            'DisplayName', sprintf('Sensor %d', iSens));
    end

    axis tight;
    legend('show','Location','best');

    %% -------------------- WAIT FOR LIVE SENSOR STREAM --------------------
    fprintf('Waiting for sensor rig stream...\n');

    validationMeans = nan(NumSens,4); % columns: mean ax, mean ay, mean az, mean |a|
    currentValidationSensor = NaN;
    firstValidSeen = false;

    while ~firstValidSeen
        line = readline(s);
        [isData, vals, validationMeans, currentValidationSensor] = ...
            parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, true);

        if isData && numel(vals) == NumValsTotal
            firstValidSeen = true;
        end
    end

    fprintf('Sensor rig stream detected.\n');
    fprintf('Sensors initialized.\n')

    %% -------------------- MOTOR START CONFIRMATION --------------------
    pause(1);

    % Indicator for the motor startup to set a delay for the acc sensors
    started = 0;

    % Acc sensor delay
    currentSimulationData.motorStartupDelay = 0;

    if ~strcmp(input("Start the motion? y/n\n",'s'),'y')
        error("Aborted");
    end

    % Remove idle samples acquired while the user was answering.
    flush(s);
    pause(0.05);

    %% -------------------- ACQUIRE DATA --------------------
    experimentTimer = tic;

    % Sensors acquire 5 s longer signal, same as original function.
    acquisitionDuration = currentSimulationData.inputSignal(end,1) + 5;

    % Preallocate with safety margin.
    estimatedRows = ceil(acquisitionDuration * sampleRate * 1.3) + 100;
    data = nan(estimatedRows, NumValsTotal);
    t_matlab = NaT(estimatedRows, 1, "TimeZone", "local");

    k = 0;
    t0_arduino_ms = NaN;

    while toc(experimentTimer) <= acquisitionDuration

        line = readline(s);
        currentMatlabTime = datetime("now", "TimeZone", "local");

        [isData, vals, validationMeans, currentValidationSensor] = ...
            parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, false);

        if ~isData
            continue;
        end

        k = k + 1;

        % Grow arrays if needed.
        if k > size(data,1)
            data = [data; nan(estimatedRows, NumValsTotal)]; %#ok<AGROW>
            t_matlab = [t_matlab; NaT(estimatedRows, 1, "TimeZone", "local")]; %#ok<AGROW>
        end

        data(k,:) = vals;
        t_matlab(k) = currentMatlabTime;

        if isnan(t0_arduino_ms)
            t0_arduino_ms = vals(1);
        end

        tPlot = (vals(1) - t0_arduino_ms) / 1000;

        % If check for a first setup loop to start the reading, then check
        % if the motorStartupDelay in seconds is reached.
        if ~started && toc(experimentTimer) > currentSimulationData.motorStartupDelay

            % Keep original timing logic as close as possible.
            SensorStart = tic;
            motionStart = toc(SensorStart);
            currentSimulationData.motionStartupDelay = motionStart;

            SendInstructionToUSB(dev,'start');
            started = 1;
        end

        % Plot sensor 1 XYZ.
        if NumSens >= 1
            s1Offset = 2; % vals: [t_ms, S1_ax, S1_ay, S1_az, S1_mag, S2_...]

            addpoints(x1_val, tPlot, vals(s1Offset));
            addpoints(y1_val, tPlot, vals(s1Offset+1));
            addpoints(z1_val, tPlot, vals(s1Offset+2));
        end

        % Plot x-axis acceleration of all sensors.
        for iSens = 1:NumSens
            axIndex = 2 + (iSens-1)*4;
            addpoints(xSensorLines(iSens), tPlot, vals(axIndex));
        end

        p1.XLim = [max(0,tPlot-10), max(10,tPlot)];
        p2.XLim = [max(0,tPlot-10), max(10,tPlot)];

        drawnow limitrate
    end

    toc(experimentTimer)

    % Trim preallocated arrays.
    data = data(1:k,:);
    t_matlab = t_matlab(1:k);

    %% -------------------- CONVERT DATA TO TABLE --------------------
    varNames = buildSensorRigVarNames(NumSens);

    sensorRigData = array2table(data, 'VariableNames', varNames);

    if ~isempty(sensorRigData)
        sensorRigData.t_arduino_s = sensorRigData.t_arduino_ms / 1000;
        sensorRigData.t_arduino_elapsed_s = ...
            (sensorRigData.t_arduino_ms - sensorRigData.t_arduino_ms(1)) / 1000;

        sensorRigData.t_matlab = t_matlab;
        sensorRigData.t_matlab_elapsed_s = ...
            seconds(sensorRigData.t_matlab - sensorRigData.t_matlab(1));

        sensorRigData = movevars(sensorRigData, 't_arduino_s', 'After', 't_arduino_ms');
        sensorRigData = movevars(sensorRigData, 't_arduino_elapsed_s', 'After', 't_arduino_s');
        sensorRigData = movevars(sensorRigData, 't_matlab', 'After', 't_arduino_elapsed_s');
        sensorRigData = movevars(sensorRigData, 't_matlab_elapsed_s', 'After', 't_matlab');
    end

    %% -------------------- VALIDATION MEAN TABLE --------------------
    validationMeanTable = array2table(validationMeans, ...
        'VariableNames', {'mean_ax_g', 'mean_ay_g', 'mean_az_g', 'mean_mag_g'});

    validationMeanTable.Sensor = (1:NumSens).';
    validationMeanTable = movevars(validationMeanTable, 'Sensor', 'Before', 1);

    %% -------------------- OPTIONAL OFFSET-CORRECTED COLUMNS --------------------
    sensorRigData = addCorrectedAccelerationColumns(sensorRigData, validationMeans, NumSens);

    %% -------------------- COMPATIBILITY OUTPUTS --------------------
    % Original function stored one sensor as dataPlate. Here we preserve that
    % behavior by storing sensor 1 as a timetable with variable Acceleration.
    % Full multi-sensor data are stored separately in sensorRigData.

    currentSimulationData.dataPlate = createSensorTimetable(sensorRigData, 1);

    if NumSens >= 2
        currentSimulationData.dataObject = createSensorTimetable(sensorRigData, 2);
    else
        currentSimulationData.dataObject = timetable;
    end

    currentSimulationData.sensorRigData = sensorRigData;
    currentSimulationData.sensorRigValidationMeans = validationMeanTable;
    currentSimulationData.sampleRate = sampleRate;

else

    tic

    SendInstructionToUSB(dev,'start');

    % Since no sensors were applied, no data exist.
    currentSimulationData.dataPlate = timetable;
    currentSimulationData.dataObject = timetable;
    currentSimulationData.sampleRate = 0;

    toc

end

end

%% ========================================================================
% LOCAL HELPER FUNCTIONS
% ========================================================================

function [isData, vals, validationMeans, currentValidationSensor] = ...
    parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, verbose)

isData = false;
vals = [];

line = strtrim(string(line));
lineChar = char(line);

if strlength(line) == 0
    return;
end

% Detect validation block lines such as: Sensor 1:
sensorToken = regexp(lineChar, '^Sensor\s+(\d+):$', 'tokens', 'once');

if ~isempty(sensorToken)
    currentValidationSensor = str2double(sensorToken{1});

    if verbose
        disp("Skipping non-data line: " + line);
    end

    return;
end

% Numeric pattern for values such as -0.1234, 1.02, 1.0E-3
numPattern = '([+-]?(?:\d+\.?\d*|\.\d+)(?:[Ee][+-]?\d+)?)';

if ~isnan(currentValidationSensor) && ...
        currentValidationSensor >= 1 && currentValidationSensor <= NumSens

    token = regexp(lineChar, ['^Mean ax \[g\]:\s*' numPattern], 'tokens', 'once');
    if ~isempty(token)
        validationMeans(currentValidationSensor, 1) = str2double(token{1});
        if verbose; disp("Skipping non-data line: " + line); end
        return;
    end

    token = regexp(lineChar, ['^Mean ay \[g\]:\s*' numPattern], 'tokens', 'once');
    if ~isempty(token)
        validationMeans(currentValidationSensor, 2) = str2double(token{1});
        if verbose; disp("Skipping non-data line: " + line); end
        return;
    end

    token = regexp(lineChar, ['^Mean az \[g\]:\s*' numPattern], 'tokens', 'once');
    if ~isempty(token)
        validationMeans(currentValidationSensor, 3) = str2double(token{1});
        if verbose; disp("Skipping non-data line: " + line); end
        return;
    end

    token = regexp(lineChar, ['^Mean \|a\| \[g\]:\s*' numPattern], 'tokens', 'once');
    if ~isempty(token)
        validationMeans(currentValidationSensor, 4) = str2double(token{1});
        if verbose; disp("Skipping non-data line: " + line); end
        return;
    end
end

% Try to parse measurement line.
% Expected:
% t_ms;S1_ax,S1_ay,S1_az,S1_mag;S2_ax,...
line2 = replace(line, ";", ",");
tokens = split(line2, ",");

valsTemp = str2double(tokens).';
NumValsTotal = 1 + NumSens*4;

if numel(valsTemp) == NumValsTotal && ~isnan(valsTemp(1))
    vals = valsTemp;
    isData = true;
else
    if verbose
        disp("Skipping non-data line: " + line);
    end
end

end

function varNames = buildSensorRigVarNames(NumSens)

baseNames = ["ax_g", "ay_g", "az_g", "mag_g"];
varNames = "t_arduino_ms";

for iSens = 1:NumSens
    sensorNames = strcat("S", string(iSens), "_", baseNames);
    varNames = [varNames, sensorNames]; %#ok<AGROW>
end

varNames = cellstr(varNames);

end

function T = addCorrectedAccelerationColumns(T, validationMeans, NumSens)

if isempty(T)
    return;
end

axisNames = ["ax_g", "ay_g", "az_g"];

for iSens = 1:NumSens

    for jAxis = 1:numel(axisNames)

        rawName  = sprintf("S%d_%s", iSens, axisNames(jAxis));
        corrName = sprintf("S%d_%s_corr", iSens, axisNames(jAxis));

        offset = validationMeans(iSens, jAxis);

        if ismember(rawName, T.Properties.VariableNames) && ~isnan(offset)
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

function TT = createSensorTimetable(T, sensorIdx)

if isempty(T) || height(T) == 0
    TT = timetable;
    return;
end

axName = sprintf("S%d_ax_g", sensorIdx);
ayName = sprintf("S%d_ay_g", sensorIdx);
azName = sprintf("S%d_az_g", sensorIdx);

neededNames = string([axName, ayName, azName]);
existingNames = string(T.Properties.VariableNames);

if ~all(ismember(neededNames, existingNames))
    TT = timetable;
    return;
end

timeVec = seconds(T.t_arduino_elapsed_s);

acceleration = [
    T.(char(axName)), ...
    T.(char(ayName)), ...
    T.(char(azName))
];

TT = timetable(timeVec, acceleration, 'VariableNames', {'Acceleration'});

end

function cleanupSensorSerial(s)

try
    flush(s);
catch
end

end
