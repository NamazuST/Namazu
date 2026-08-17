%------------------------------------------------------------
% Forced-vibration frequency estimation using FRFs
% Input-output modal peak picking
%------------------------------------------------------------
clc; clear all; close all; fclose all;
warning off;

%------------------------------------------------------------
% Measurement parameters
%------------------------------------------------------------
g = 9.81;

% Output accelerometer offsets and sensitivities
setp_out = [0.0 0.0 0.0 0.0];       
sens_out = [0.1072 0.1320 0.1276 0.1329]./g;  % V/(m/s^2)

% Input sensor calibration
% If input is already in physical units, use setp_in = 0, sens_in = 1.
setp_in = 0.0;
sens_in = 1.0;

nchanel = length(sens_out);

f1 = fopen('results_forced_FRF.txt','w');

% Number of measurements
n_med = 100;
med_label = num2cell(1:n_med);

% Peak-picking parameters
level = 0.03 * ones(1,n_med);   % relative threshold
min_peak_distance_hz = 15;      % minimum distance between modal peaks
delta_f = 5;                    % local interpolation range around each peak
fmin = 0.5;                     % lower frequency limit for peak search
fmax = 100;                     % upper frequency limit for peak search

% Plot flag
iflag = 1;

%------------------------------------------------------------
% Main loop
%------------------------------------------------------------
for i_med = 1:1   % change to 1:n_med for batch processing

    clear freqv zeta H coh acc input_signal

    filename = strcat('teste_', num2str(i_med));
    fprintf('Processing file No.: %s ...\n', filename);

    %--------------------------------------------------------
    % Read measured input signal
    %--------------------------------------------------------
    % Adjust this filename to your actual input measurement file
    filename_input = strcat(filename, '_input.dat');

    data_in = read_two_column_file(filename_input);
    time = data_in(:,1);
    input_raw = data_in(:,2);

    dt = time(2) - time(1);
    fs = 1/dt;
    T = time(end) - time(1);
    df = 1/T;

    input_signal = (input_raw - setp_in) ./ sens_in;
    input_signal = input_signal - mean(input_signal);

    %--------------------------------------------------------
    % Read output acceleration channels
    %--------------------------------------------------------
    for icanal = 1:nchanel

        filenamech = strcat(filename, '_', num2str(icanal), '.dat');

        data = read_two_column_file(filenamech);

        time_out = data(:,1);
        acel_raw = data(:,2);

        % Optional safety check
        if length(time_out) ~= length(time)
            error('Input and output channel have different lengths.');
        end

        acc(:,icanal) = (acel_raw - setp_out(icanal)) ./ sens_out(icanal);
        acc(:,icanal) = acc(:,icanal) - mean(acc(:,icanal));

        arms(i_med,icanal) = rms(acc(:,icanal));

    end

    %--------------------------------------------------------
    % Estimate FRFs using Welch-based transfer function estimate
    %--------------------------------------------------------
    N = length(input_signal);

    % Welch parameters
    nfft = 2^nextpow2(N);
    window_length = round(N/8);
    window = hann(window_length);
    noverlap = round(0.5 * window_length);

    for icanal = 1:nchanel

        % H(:,icanal): FRF from measured input to output acceleration
        [H(:,icanal), freq] = tfestimate( ...
            input_signal, ...
            acc(:,icanal), ...
            window, ...
            noverlap, ...
            nfft, ...
            fs);

        % Coherence, useful for quality control
        [coh(:,icanal), ~] = mscohere( ...
            input_signal, ...
            acc(:,icanal), ...
            window, ...
            noverlap, ...
            nfft, ...
            fs);
    end

    %--------------------------------------------------------
    % Construct FRF envelope over all output channels
    %--------------------------------------------------------
    envfrf = max(abs(H), [], 2);

    df_frf = freq(2) - freq(1);

    idx_search = find(freq >= fmin & freq <= fmax);
    env_search = envfrf(idx_search);

    maxvalue = max(env_search);

    [pks, locs_local] = findpeaks( ...
        env_search, ...
        'MinPeakHeight', level(i_med)*maxvalue, ...
        'MinPeakDistance', round(min_peak_distance_hz/df_frf));

    locs = idx_search(locs_local);
    npks = length(pks);

    %--------------------------------------------------------
    % Optional plotting: input, outputs, FRFs, envelope
    %--------------------------------------------------------
    if iflag == 1

        h1 = figure;
        tiledlayout(3, nchanel, 'TileSpacing', 'compact');

        % Input signal
        nexttile([1 nchanel]);
        plot(time, input_signal, '-k');
        xlabel('Time [s]');
        ylabel('Input');
        title(['Measured input - Measurement #' num2str(med_label{i_med})]);

        % Output accelerations
        for icanal = 1:nchanel
            nexttile;
            plot(time, acc(:,icanal));
            xlabel('Time [s]');
            ylabel('Acc. [m/s^2]');
            title(['Output ch. ' num2str(icanal)]);
        end

        % FRFs
        for icanal = 1:nchanel
            nexttile;
            plot(freq, abs(H(:,icanal)));
            xlabel('f [Hz]');
            ylabel('|H(f)|');
            xlim([0 fmax]);
            title(['FRF ch. ' num2str(icanal)]);
        end

        h2 = figure;
        subplot(2,1,1);
        plot(freq, envfrf, '-k');
        hold on;
        plot(freq(locs), envfrf(locs), 'or');
        xlabel('f [Hz]');
        ylabel('FRF envelope');
        xlim([0 fmax]);
        legend('FRF envelope', 'identified peaks');
        title('FRF envelope and selected modal peaks');

        subplot(2,1,2);
        plot(freq, coh);
        xlabel('f [Hz]');
        ylabel('Coherence');
        xlim([0 fmax]);
        ylim([0 1]);
        title('Input-output coherence');
    end

    %--------------------------------------------------------
    % Refine modal frequencies by local spline interpolation
    %--------------------------------------------------------
    npt = round(delta_f / df_frf);

    for ipeak = 1:npks

        idx_left  = max(locs(ipeak)-npt, 1);
        idx_right = min(locs(ipeak)+npt, length(freq));

        int_freq = linspace(freq(idx_left), freq(idx_right), 5000);

        s = spline( ...
            freq(idx_left:idx_right), ...
            envfrf(idx_left:idx_right), ...
            int_freq);

        [pv, pp] = max(s);

        freqv(ipeak) = int_freq(pp);

        %----------------------------------------------------
        % Damping estimate using half-power bandwidth
        % valid mainly for lightly damped, well-separated modes
        %----------------------------------------------------
        half_power_level = pv / sqrt(2);

        % Left crossing
        left_candidates = find(s(1:pp) <= half_power_level);
        if isempty(left_candidates)
            f_left = NaN;
        else
            il = left_candidates(end);
            if il < pp
                f_left = interp1( ...
                    s(il:il+1), ...
                    int_freq(il:il+1), ...
                    half_power_level, ...
                    'linear', ...
                    'extrap');
            else
                f_left = NaN;
            end
        end

        % Right crossing
        right_candidates = find(s(pp:end) <= half_power_level);
        if isempty(right_candidates)
            f_right = NaN;
        else
            ir = pp + right_candidates(1) - 1;
            if ir > pp
                f_right = interp1( ...
                    s(ir-1:ir), ...
                    int_freq(ir-1:ir), ...
                    half_power_level, ...
                    'linear', ...
                    'extrap');
            else
                f_right = NaN;
            end
        end

        if ~isnan(f_left) && ~isnan(f_right)
            zeta(ipeak) = (f_right - f_left) / (2 * freqv(ipeak));
        else
            zeta(ipeak) = NaN;
        end
    end

    %--------------------------------------------------------
    % Print and store results
    %--------------------------------------------------------
    fprintf('Sample:%3i  freq(Hz):', i_med);
    fprintf(' %+5.8f', freqv(1:npks));
    fprintf(' zeta(-): ');
    fprintf(' %+5.8f', zeta(1:npks));
    fprintf('\n');

    fprintf(f1, ' %3i', i_med);
    fprintf(f1, ' %+5.8f', freqv(1:npks));
    fprintf(f1, ' %+5.8f', zeta(1:npks));
    fprintf(f1, ' \n');

    freqsample(i_med,1:npks) = freqv(1:npks);
    zetasample(i_med,1:npks) = zeta(1:npks);

end

fclose(f1);

%------------------------------------------------------------
% Helper function for reading files of the form:
% (time, value)
%------------------------------------------------------------
function data = read_two_column_file(filename)

    raw = fileread(filename);

    % Remove parentheses
    raw = regexprep(raw, '[()]', '');

    % Read two comma-separated numerical columns
    C = textscan(raw, '%f%f', ...
        'Delimiter', ',', ...
        'MultipleDelimsAsOne', true, ...
        'CollectOutput', true);

    data = C{1};

    if size(data,2) ~= 2
        error('Could not read two numerical columns from file: %s', filename);
    end
end