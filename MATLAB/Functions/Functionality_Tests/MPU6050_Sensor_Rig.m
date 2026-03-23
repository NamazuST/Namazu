%% -------------------- SETTINGS --------------------
port = "COM5";          % <- change this to your Arduino port
baud = 115200;
N = 1000;               % number of valid samples to acquire

%% -------------------- CONNECT --------------------
% If you still have an old serialport object hanging around, clear it first.
clear s

s = serialport(port, baud);
configureTerminator(s, "CR/LF");
s.Timeout = 5;

% Clear any stale bytes already sitting in the buffer
flush(s);

% Give the Arduino a moment in case it restarts when the port opens
pause(2);

%% -------------------- READ DATA --------------------
data = nan(N, 12);
k = 0;

while k < N
    line = readline(s);          % read one full line
    line = strtrim(line);        % remove stray whitespace

    % Replace sensor separators ";" by ","
    line2 = replace(line, ";", ",");

    % Try to parse 12 floating-point numbers
    vals = sscanf(line2, '%f,').';

    if numel(vals) == 12
        k = k + 1;
        data(k, :) = vals;
    else
        % This skips startup text like:
        % "MPU6050 3-Sensor Raw Acceleration Test"
        % "Initializing IMU 1", etc.
        disp("Skipping non-data line: " + line);
    end
end

%% -------------------- CLOSE --------------------
clear s

%% -------------------- LABEL COLUMNS --------------------
varNames = { ...
    'S1_ax_g','S1_ay_g','S1_az_g','S1_mag_g', ...
    'S2_ax_g','S2_ay_g','S2_az_g','S2_mag_g', ...
    'S3_ax_g','S3_ay_g','S3_az_g','S3_mag_g'};

T = array2table(data, 'VariableNames', varNames);

disp(T(1:10,:))