%% -------------------- SETTINGS --------------------
port = "COM9";          % <- change this to your Arduino port
baud = 115200;
N = 1000;               % number of valid samples to acquire
NumSens = 5;            % number of sensors

NumValsPerSens = 4;                 % ax_g, ay_g, az_g, mag_g
NumSensorVals = NumSens * NumValsPerSens;
NumValsTotal = 1 + NumSensorVals;   % +1 because of Arduino t_ms timestamp

%% -------------------- CONNECT --------------------
clear s

s = serialport(port, baud);
configureTerminator(s, "CR/LF");
s.Timeout = 5;

flush(s);

% Give Arduino time to restart after opening serial port
pause(2);

%% -------------------- READ DATA --------------------
data = nan(N, NumValsTotal);
t_matlab = NaT(N, 1, "TimeZone", "local");

% Store validation means from Arduino startup output
% columns: ax, ay, az, mag
validationMeans = nan(NumSens, 4);
currentValidationSensor = NaN;

k = 0;

while k < N
    line = readline(s);

    % MATLAB timestamp when the line was received
    currentMatlabTime = datetime("now", "TimeZone", "local");

    line = strtrim(line);

    %% -------- Try to extract validation information --------

    % Detect lines like: Sensor 1:
    sensorToken = regexp(line, '^Sensor\s+(\d+):$', 'tokens', 'once');
    if ~isempty(sensorToken)
        currentValidationSensor = str2double(sensorToken{1});
        disp("Skipping non-data line: " + line);
        continue;
    end

    % Numeric pattern for numbers such as -0.1234, 1.02, 1.0E-3
    numPattern = '([+-]?(?:\d+\.?\d*|\.\d+)(?:[Ee][+-]?\d+)?)';

    if ~isnan(currentValidationSensor) && currentValidationSensor >= 1 && currentValidationSensor <= NumSens

        token = regexp(line, ['^Mean ax \[g\]:\s*' numPattern], 'tokens', 'once');
        if ~isempty(token)
            validationMeans(currentValidationSensor, 1) = str2double(token{1});
            disp("Skipping non-data line: " + line);
            continue;
        end

        token = regexp(line, ['^Mean ay \[g\]:\s*' numPattern], 'tokens', 'once');
        if ~isempty(token)
            validationMeans(currentValidationSensor, 2) = str2double(token{1});
            disp("Skipping non-data line: " + line);
            continue;
        end

        token = regexp(line, ['^Mean az \[g\]:\s*' numPattern], 'tokens', 'once');
        if ~isempty(token)
            validationMeans(currentValidationSensor, 3) = str2double(token{1});
            disp("Skipping non-data line: " + line);
            continue;
        end

        token = regexp(line, ['^Mean \|a\| \[g\]:\s*' numPattern], 'tokens', 'once');
        if ~isempty(token)
            validationMeans(currentValidationSensor, 4) = str2double(token{1});
            disp("Skipping non-data line: " + line);
            continue;
        end
    end

    %% -------- Try to parse numeric measurement line --------

    % Replace sensor separators ";" by ","
    line2 = replace(line, ";", ",");

    % Parse numeric values
    vals = sscanf(line2, '%f,').';

    if numel(vals) == NumValsTotal
        k = k + 1;
        data(k, :) = vals;
        t_matlab(k) = currentMatlabTime;
    else
        disp("Skipping non-data line: " + line);
    end
end

%% -------------------- CLOSE --------------------
clear s

%% -------------------- LABEL COLUMNS --------------------
baseNames = ["ax_g", "ay_g", "az_g", "mag_g"];

varNames = "t_arduino_ms";

for iSens = 1:NumSens
    sensorNames = strcat("S", string(iSens), "_", baseNames);
    varNames = [varNames, sensorNames];
end

T = array2table(data, 'VariableNames', cellstr(varNames));

%% -------------------- ADD TIMESTAMPS --------------------
T.t_arduino_s = T.t_arduino_ms / 1000;
T.t_matlab = t_matlab;

% MATLAB elapsed time since first valid received sample
T.t_matlab_elapsed_s = seconds(T.t_matlab - T.t_matlab(1));

% Reorder timestamp columns
T = movevars(T, 't_arduino_s', 'After', 't_arduino_ms');
T = movevars(T, 't_matlab', 'After', 't_arduino_s');
T = movevars(T, 't_matlab_elapsed_s', 'After', 't_matlab');

%% -------------------- VALIDATION MEAN TABLE --------------------
validationMeanTable = array2table(validationMeans, ...
    'VariableNames', {'mean_ax_g', 'mean_ay_g', 'mean_az_g', 'mean_mag_g'});

validationMeanTable.Sensor = (1:NumSens).';
validationMeanTable = movevars(validationMeanTable, 'Sensor', 'Before', 1);

disp("Extracted static validation means:");
disp(validationMeanTable);

%% -------------------- SUBTRACT STATIC MEANS --------------------
% Correct ax, ay, az by subtracting the static validation means.
% This gives dynamic acceleration relative to the initial rest condition.

axisNames = ["ax_g", "ay_g", "az_g"];

for iSens = 1:NumSens
    for jAxis = 1:numel(axisNames)
        rawName = sprintf("S%d_%s", iSens, axisNames(jAxis));
        corrName = sprintf("S%d_%s_corr", iSens, axisNames(jAxis));

        offset = validationMeans(iSens, jAxis);

        if ~isnan(offset)
            T.(corrName) = T.(rawName) - offset;
        else
            T.(corrName) = nan(height(T), 1);
        end
    end

    % Recompute corrected magnitude
    corrAx = sprintf("S%d_ax_g_corr", iSens);
    corrAy = sprintf("S%d_ay_g_corr", iSens);
    corrAz = sprintf("S%d_az_g_corr", iSens);
    corrMag = sprintf("S%d_mag_g_corr", iSens);

    T.(corrMag) = sqrt(T.(corrAx).^2 + T.(corrAy).^2 + T.(corrAz).^2);
end

disp("First 10 rows of corrected table:");
disp(T(1:10,:));

%% -------------------- OPTIONAL PLOT: RAW X-ACCELERATION --------------------
t_plot = T.t_arduino_s - T.t_arduino_s(1);

figure;
hold on;
grid on;
box on;

for iSens = 1:NumSens
    varName = sprintf("S%d_ax_g", iSens);
    plot(t_plot, T.(varName), 'DisplayName', sprintf("Sensor %d raw", iSens));
end

xlabel("Time [s]");
ylabel("Raw x-acceleration [g]");
title("Raw x-axis acceleration of all sensors");
legend("Location", "best");
hold off;

%% -------------------- OPTIONAL PLOT: CORRECTED X-ACCELERATION --------------------
figure;
hold on;
grid on;
box on;

for iSens = 1:NumSens
    varName = sprintf("S%d_ax_g_corr", iSens);
    plot(t_plot, T.(varName), 'DisplayName', sprintf("Sensor %d corrected", iSens));
end

xlabel("Time [s]");
ylabel("Corrected x-acceleration [g]");
title("Corrected x-axis acceleration of all sensors");
legend("Location", "best");
hold off;