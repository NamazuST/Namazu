function state = LiveSingleSensorFFTMonitor(varargin)
% LiveSingleSensorFFTMonitor
%
% Continuous one-sensor acceleration and sliding FFT monitor for the top
% MPU6050 sensor. The function reads the MATLAB-compatible serial stream,
% plots the selected acceleration direction, recomputes a sliding FFT, and
% marks the strongest spectral peaks as live eigenfrequency estimates.
%
% Expected serial line format:
%   t_ms;S1_ax_g,S1_ay_g,S1_az_g,S1_mag_g
%
% Usage:
%   state = LiveSingleSensorFFTMonitor();
%   state = LiveSingleSensorFFTMonitor("Port", "COM9", "Direction", "y");
%   state = LiveSingleSensorFFTMonitor("FFTWindowSeconds", 12, ...
%       "FMax", 100, "MaxPeaks", 4);

parser = inputParser;
parser.FunctionName = mfilename;

addParameter(parser, "Port", "COM9", @(x) ischar(x) || isstring(x));
addParameter(parser, "Baud", 1000000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "Direction", "y", @(x) ischar(x) || isstring(x));
addParameter(parser, "UseCorrectedData", true, @(x) islogical(x) || isnumeric(x));
addParameter(parser, "NominalSampleRate", 500, @(x) isnumeric(x) && isscalar(x) && x > 0);

addParameter(parser, "PlotWindowSeconds", 10, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "FFTWindowSeconds", 10, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "PlotUpdateSeconds", 0.10, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "FFTUpdateSeconds", 0.75, @(x) isnumeric(x) && isscalar(x) && x > 0);

addParameter(parser, "FMin", 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "FMax", 100, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "FrequencyResolutionHz", 0.1, @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && x > 0));
addParameter(parser, "RelativePeakLevel", 0.05, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "MinPeakDistanceHz", 10, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "MaxPeaks", 4, @(x) isnumeric(x) && isscalar(x) && x > 0 && mod(x, 1) == 0);
addParameter(parser, "MinFFTSamples", 128, @(x) isnumeric(x) && isscalar(x) && x > 0);

parse(parser, varargin{:});

port = string(parser.Results.Port);
baud = parser.Results.Baud;
direction = lower(strtrim(string(parser.Results.Direction)));
useCorrectedData = logical(parser.Results.UseCorrectedData);
nominalSampleRate = parser.Results.NominalSampleRate;

plotWindowSeconds = parser.Results.PlotWindowSeconds;
fftWindowSeconds = parser.Results.FFTWindowSeconds;
plotUpdateSeconds = parser.Results.PlotUpdateSeconds;
fftUpdateSeconds = parser.Results.FFTUpdateSeconds;

fftSettings = struct();
fftSettings.fMin = parser.Results.FMin;
fftSettings.fMax = parser.Results.FMax;
fftSettings.frequencyResolutionHz = parser.Results.FrequencyResolutionHz;
fftSettings.relativePeakLevel = parser.Results.RelativePeakLevel;
fftSettings.minPeakDistanceHz = parser.Results.MinPeakDistanceHz;
fftSettings.maxPeaks = parser.Results.MaxPeaks;
fftSettings.minFFTSamples = parser.Results.MinFFTSamples;

[quantityIndex, quantityLabel, quantityUnitLabel] = parseQuantityOfInterest(direction);

portList = serialportlist("available");

if ~any(strcmp(string(portList), port))
    error("Sensor port %s not found/open or port is in use. Check USB connection.", port);
end

ui = setupMonitorFigure(quantityLabel, quantityUnitLabel, plotWindowSeconds, fftSettings);

fprintf("Opening top-sensor serial port %s at %d baud...\n", port, baud);
s = serialport(port, baud);
configureTerminator(s, "CR/LF");
s.Timeout = 0.25;
cleanupObj = onCleanup(@() cleanupSensorSerial(s));

flush(s);
pause(1.5);

NumSens = 1;
NumValsTotal = 1 + NumSens*4;
validationMeans = nan(NumSens, 4);
currentValidationSensor = NaN;
pendingVals = [];

fprintf("Waiting for top-sensor live stream. Press Stop, Esc, or Q to end.\n");

while isempty(pendingVals) && isvalid(ui.figure) && ~getappdata(ui.figure, 'StopRequested')
    line = readSerialLineNoThrow(s);

    if strlength(line) == 0
        drawnow limitrate
        continue;
    end

    [isData, vals, validationMeans, currentValidationSensor] = ...
        parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, true);

    if isData && numel(vals) == NumValsTotal
        pendingVals = vals;
    end

    drawnow limitrate
end

tBuffer = zeros(0, 1);
yBuffer = zeros(0, 1);
t0ArduinoMs = NaN;
totalSamples = 0;
lastPlotUpdate = -Inf;
lastFFTUpdate = -Inf;
lastFFTResult = createEmptyFFTResult();
loopTimer = tic;
dataModeLabel = "raw";
maxBufferSeconds = max(plotWindowSeconds, fftWindowSeconds) + 5;

while isvalid(ui.figure) && ~getappdata(ui.figure, 'StopRequested')
    loopSeconds = toc(loopTimer);

    if ~isempty(pendingVals)
        vals = pendingVals;
        pendingVals = [];
        isData = true;
    else
        line = readSerialLineNoThrow(s);

        if strlength(line) == 0
            drawnow limitrate
            continue;
        end

        [isData, vals, validationMeans, currentValidationSensor] = ...
            parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, false);
    end

    if isData && numel(vals) == NumValsTotal
        if isnan(t0ArduinoMs)
            t0ArduinoMs = vals(1);
        end

        tSeconds = (vals(1) - t0ArduinoMs) / 1000;
        [yValue, dataModeLabel] = selectAccelerationValue( ...
            vals, quantityIndex, validationMeans, useCorrectedData);

        if isfinite(tSeconds) && isfinite(yValue)
            tBuffer(end + 1, 1) = tSeconds; %#ok<AGROW>
            yBuffer(end + 1, 1) = yValue; %#ok<AGROW>
            totalSamples = totalSamples + 1;

            keep = tBuffer >= max(0, tSeconds - maxBufferSeconds);
            tBuffer = tBuffer(keep);
            yBuffer = yBuffer(keep);
        end
    end

    if loopSeconds - lastPlotUpdate >= plotUpdateSeconds
        ui = updateAccelerationPlot( ...
            ui, tBuffer, yBuffer, plotWindowSeconds, dataModeLabel, nominalSampleRate);
        lastPlotUpdate = loopSeconds;
    end

    if loopSeconds - lastFFTUpdate >= fftUpdateSeconds
        lastFFTResult = computeSlidingFFT(tBuffer, yBuffer, fftWindowSeconds, fftSettings);
        ui = updateFFTPlot(ui, lastFFTResult, fftWindowSeconds, fftSettings);
        lastFFTUpdate = loopSeconds;
    end

    drawnow limitrate
end

state = struct();
state.port = port;
state.baud = baud;
state.direction = direction;
state.useCorrectedData = useCorrectedData;
state.nominalSampleRate = nominalSampleRate;
state.totalSamples = totalSamples;
state.stoppedAt = datetime("now", "TimeZone", "local");
state.lastFFT = lastFFTResult;
state.validationMeans = validationMeans;

clear cleanupObj
fprintf("Live FFT monitor stopped. Samples read: %d\n", totalSamples);

end

%% ========================================================================
% LOCAL HELPER FUNCTIONS
% ========================================================================

function ui = setupMonitorFigure(quantityLabel, quantityUnitLabel, plotWindowSeconds, fftSettings)

ui = struct();
ui.figure = figure("Name", "Live top-sensor FFT monitor", "NumberTitle", "off");
setappdata(ui.figure, 'StopRequested', false);
ui.figure.KeyPressFcn = @keyPressStop;

layout = tiledlayout(ui.figure, 2, 1, "TileSpacing", "compact", "Padding", "compact");

ui.accelerationAxes = nexttile(layout, 1);
ui.accelerationLine = animatedline(ui.accelerationAxes, ...
    "LineWidth", 1.2, ...
    "Color", [0.0000 0.4470 0.7410]);
grid(ui.accelerationAxes, "on");
box(ui.accelerationAxes, "on");
xlabel(ui.accelerationAxes, "Arduino elapsed time [s]");
ylabel(ui.accelerationAxes, quantityUnitLabel, "Interpreter", "none");
title(ui.accelerationAxes, sprintf("%s acceleration, last %.1f s", ...
    quantityLabel, plotWindowSeconds), "Interpreter", "none");

ui.fftAxes = nexttile(layout, 2);
ui.fftLine = plot(ui.fftAxes, NaN, NaN, ...
    "LineWidth", 1.2, ...
    "Color", [0.1500 0.1500 0.1500]);
hold(ui.fftAxes, "on");
grid(ui.fftAxes, "on");
box(ui.fftAxes, "on");
xlabel(ui.fftAxes, "Frequency [Hz]");
ylabel(ui.fftAxes, "|FFT| [g]");
xlim(ui.fftAxes, [fftSettings.fMin fftSettings.fMax]);
title(ui.fftAxes, "Waiting for enough data...", "Interpreter", "none");

ui.peakMarkers = gobjects(0);
ui.peakLabels = gobjects(0);

ui.stopButton = uicontrol(ui.figure, ...
    "Style", "pushbutton", ...
    "String", "Stop", ...
    "Units", "normalized", ...
    "Position", [0.90 0.94 0.08 0.045], ...
    "Callback", @(~, ~) setappdata(ui.figure, 'StopRequested', true));

end

function keyPressStop(fig, event)

if ismember(lower(string(event.Key)), ["escape", "q"])
    setappdata(fig, 'StopRequested', true);
end

end

function line = readSerialLineNoThrow(s)

try
    line = string(readline(s));
catch
    line = "";
end

end

function [quantityIndex, quantityLabel, quantityUnitLabel] = parseQuantityOfInterest(quantityOfInterest)

q = lower(strtrim(string(quantityOfInterest)));
q = replace(q, "-", "");
q = replace(q, "_", "");
q = replace(q, " ", "");

switch q
    case {"x", "ax", "axg"}
        quantityIndex = 1;
        quantityLabel = "x-axis";
        quantityUnitLabel = "x acceleration [g]";
    case {"y", "ay", "ayg"}
        quantityIndex = 2;
        quantityLabel = "y-axis";
        quantityUnitLabel = "y acceleration [g]";
    case {"z", "az", "azg"}
        quantityIndex = 3;
        quantityLabel = "z-axis";
        quantityUnitLabel = "z acceleration [g]";
    case {"mag", "magnitude", "norm"}
        quantityIndex = 4;
        quantityLabel = "magnitude";
        quantityUnitLabel = "acceleration magnitude [g]";
    otherwise
        error('Direction must be "x", "y", "z", or "mag".');
end

end

function [y, dataModeLabel] = selectAccelerationValue(vals, quantityIndex, validationMeans, useCorrectedData)

baseIndex = 2;
dataModeLabel = "raw";

if quantityIndex <= 3
    y = vals(baseIndex + quantityIndex - 1);

    if useCorrectedData
        offset = validationMeans(1, quantityIndex);

        if isfinite(offset)
            y = y - offset;
            dataModeLabel = "corrected";
        end
    end

else
    if useCorrectedData && all(isfinite(validationMeans(1, 1:3)))
        corrected = [
            vals(baseIndex) - validationMeans(1, 1), ...
            vals(baseIndex + 1) - validationMeans(1, 2), ...
            vals(baseIndex + 2) - validationMeans(1, 3)
        ];
        y = sqrt(sum(corrected.^2));
        dataModeLabel = "corrected";
    else
        y = vals(baseIndex + 3);
    end
end

end

function ui = updateAccelerationPlot(ui, tBuffer, yBuffer, plotWindowSeconds, dataModeLabel, nominalSampleRate)

if isempty(tBuffer)
    return;
end

tMax = tBuffer(end);
idx = tBuffer >= max(0, tMax - plotWindowSeconds);
tPlot = tBuffer(idx);
yPlot = yBuffer(idx);

clearpoints(ui.accelerationLine);
addpoints(ui.accelerationLine, tPlot, yPlot);

ui.accelerationAxes.XLim = [max(0, tMax - plotWindowSeconds), ...
    max(plotWindowSeconds, tMax)];

if any(isfinite(yPlot))
    yMin = min(yPlot, [], "omitnan");
    yMax = max(yPlot, [], "omitnan");
    yPad = max(0.02, 0.10 * max(abs([yMin, yMax])));

    yMin = yMin - yPad;
    yMax = yMax + yPad;

    ui.accelerationAxes.YLim = [yMin yMax];
end

fsRecent = estimateSampleRate(tPlot);

if isfinite(fsRecent)
    fsText = sprintf("measured Fs %.1f Hz", fsRecent);
else
    fsText = sprintf("nominal Fs %.1f Hz", nominalSampleRate);
end

title(ui.accelerationAxes, sprintf("Y acceleration (%s), last %.1f s, %s", ...
    dataModeLabel, plotWindowSeconds, fsText), "Interpreter", "none");

end

function result = computeSlidingFFT(tBuffer, yBuffer, fftWindowSeconds, settings)

result = createEmptyFFTResult();

if isempty(tBuffer)
    result.status = "Waiting for data";
    return;
end

tMax = tBuffer(end);
idx = tBuffer >= max(0, tMax - fftWindowSeconds);
t = tBuffer(idx);
y = yBuffer(idx);

validRows = isfinite(t) & isfinite(y);
t = t(validRows);
y = y(validRows);

if numel(t) < settings.minFFTSamples
    result.status = sprintf("Waiting for at least %d samples", settings.minFFTSamples);
    return;
end

[t, uniqueIdx] = unique(t, "stable");
y = y(uniqueIdx);

dt = median(diff(t));

if ~isfinite(dt) || dt <= 0
    result.status = "Invalid time base";
    return;
end

fs = 1 / dt;
fNyquist = fs / 2;
fMaxUsed = min(settings.fMax, 0.98 * fNyquist);

if fMaxUsed <= settings.fMin
    result.status = sprintf("FMax %.2f Hz is above usable Nyquist %.2f Hz", ...
        settings.fMax, fNyquist);
    return;
end

tUniform = (t(1):dt:t(end)).';
yUniform = interp1(t, y, tUniform, "linear", "extrap");
yUniform = yUniform - mean(yUniform, "omitnan");
nSamples = numel(yUniform);

if nSamples < settings.minFFTSamples
    result.status = sprintf("Waiting for at least %d uniform samples", settings.minFFTSamples);
    return;
end

window = hannWindow(nSamples);
yWindowed = yUniform .* window;
nFFT = nSamples;

if ~isempty(settings.frequencyResolutionHz)
    nFFT = max(nFFT, ceil(fs / settings.frequencyResolutionHz));
    nFFT = 2^nextpow2(nFFT);
end

df = fs / nFFT;
nFreq = floor(nFFT / 2) + 1;
freq = (0:nFreq - 1).' * df;
fftAbs = 2 * abs(fft(yWindowed, nFFT)) / sum(window);
fftAbs = fftAbs(1:nFreq);

idxSearch = find(freq >= settings.fMin & freq <= fMaxUsed);

if isempty(idxSearch)
    result.status = "No FFT bins inside search range";
    return;
end

searchAmplitude = fftAbs(idxSearch);
maxAmplitude = max(searchAmplitude);

if ~isfinite(maxAmplitude) || maxAmplitude <= 0
    result.status = "FFT amplitude is empty";
    return;
end

[pks, locsLocal] = findpeaks( ...
    searchAmplitude, ...
    "MinPeakHeight", settings.relativePeakLevel * maxAmplitude, ...
    "MinPeakDistance", max(1, round(settings.minPeakDistanceHz / df)));

if isempty(pks)
    result.status = sprintf("No peaks in %.2f Hz to %.2f Hz", settings.fMin, fMaxUsed);
else
    locs = idxSearch(locsLocal);
    [~, strongestIdx] = sort(pks, "descend");
    strongestIdx = strongestIdx(1:min(settings.maxPeaks, numel(strongestIdx)));
    locs = locs(strongestIdx);
    pks = pks(strongestIdx);
    [locs, sortIdx] = sort(locs);
    pks = pks(sortIdx);

    [peakFreqHz, peakAmplitude] = refinePeaksParabolic(freq, fftAbs, locs, pks);
    result.peakFreqHz = peakFreqHz;
    result.peakAmplitude = peakAmplitude;
    result.status = formatPeakStatus(peakFreqHz);
end

result.freq = freq;
result.fftAbs = fftAbs;
result.fs = fs;
result.df = df;
result.fNyquist = fNyquist;
result.fMaxUsed = fMaxUsed;
result.windowSeconds = tUniform(end) - tUniform(1);
result.nSamples = nSamples;
result.nFFT = nFFT;

end

function result = createEmptyFFTResult()

result = struct();
result.freq = [];
result.fftAbs = [];
result.peakFreqHz = [];
result.peakAmplitude = [];
result.fs = NaN;
result.df = NaN;
result.fNyquist = NaN;
result.fMaxUsed = NaN;
result.windowSeconds = NaN;
result.nSamples = 0;
result.nFFT = 0;
result.status = "Waiting for data";

end

function window = hannWindow(n)

if n <= 1
    window = ones(n, 1);
else
    k = (0:n - 1).';
    window = 0.5 - 0.5*cos(2*pi*k/(n - 1));
end

end

function [peakFreqHz, peakAmplitude] = refinePeaksParabolic(freq, fftAbs, locs, pks)

peakFreqHz = freq(locs).';
peakAmplitude = pks(:).';

for iPeak = 1:numel(locs)
    idx = locs(iPeak);

    if idx <= 1 || idx >= numel(fftAbs)
        continue;
    end

    yLeft = fftAbs(idx - 1);
    yCenter = fftAbs(idx);
    yRight = fftAbs(idx + 1);
    denom = yLeft - 2*yCenter + yRight;

    if ~isfinite(denom) || abs(denom) < eps
        continue;
    end

    delta = 0.5 * (yLeft - yRight) / denom;

    if abs(delta) > 1
        continue;
    end

    df = freq(2) - freq(1);
    peakFreqHz(iPeak) = freq(idx) + delta * df;
    peakAmplitude(iPeak) = yCenter - 0.25 * (yLeft - yRight) * delta;
end

end

function status = formatPeakStatus(peakFreqHz)

if isempty(peakFreqHz)
    status = "No peaks";
    return;
end

parts = strings(1, numel(peakFreqHz));

for iPeak = 1:numel(peakFreqHz)
    parts(iPeak) = sprintf("%.2f Hz", peakFreqHz(iPeak));
end

status = "Peaks: " + strjoin(parts, ", ");

end

function ui = updateFFTPlot(ui, result, fftWindowSeconds, settings)

if isempty(result.freq) || isempty(result.fftAbs)
    title(ui.fftAxes, result.status, "Interpreter", "none");
    return;
end

set(ui.fftLine, "XData", result.freq, "YData", result.fftAbs);
deleteValidGraphics(ui.peakMarkers);
deleteValidGraphics(ui.peakLabels);
ui.peakMarkers = gobjects(0);
ui.peakLabels = gobjects(0);

if ~isempty(result.peakFreqHz)
    ui.peakMarkers = plot(ui.fftAxes, result.peakFreqHz, result.peakAmplitude, ...
        "o", ...
        "LineWidth", 1.2, ...
        "MarkerSize", 6, ...
        "Color", [0.8500 0.3250 0.0980], ...
        "MarkerFaceColor", [0.8500 0.3250 0.0980]);

    ui.peakLabels = gobjects(numel(result.peakFreqHz), 1);

    for iPeak = 1:numel(result.peakFreqHz)
        ui.peakLabels(iPeak) = text(ui.fftAxes, ...
            result.peakFreqHz(iPeak), ...
            result.peakAmplitude(iPeak), ...
            sprintf(" %.2f Hz", result.peakFreqHz(iPeak)), ...
            "VerticalAlignment", "bottom", ...
            "Interpreter", "none");
    end
end

xlim(ui.fftAxes, [settings.fMin max(settings.fMin + eps, result.fMaxUsed)]);

if any(isfinite(result.fftAbs))
    yMax = max(result.fftAbs(result.freq <= result.fMaxUsed), [], "omitnan");

    if isfinite(yMax) && yMax > 0
        ylim(ui.fftAxes, [0 1.15*yMax]);
    end
end

title(ui.fftAxes, sprintf("%s | window %.1f s, Fs %.1f Hz, df %.3f Hz", ...
    result.status, fftWindowSeconds, result.fs, result.df), "Interpreter", "none");

end

function deleteValidGraphics(handles)

if isempty(handles)
    return;
end

for i = 1:numel(handles)
    if isgraphics(handles(i))
        delete(handles(i));
    end
end

end

function fs = estimateSampleRate(t)

t = double(t(:));
t = t(isfinite(t));

if numel(t) < 2
    fs = NaN;
    return;
end

dt = median(diff(t));

if isfinite(dt) && dt > 0
    fs = 1 / dt;
else
    fs = NaN;
end

end

function [isData, vals, validationMeans, currentValidationSensor] = ...
    parseSensorRigLine(line, NumSens, validationMeans, currentValidationSensor, verbose)

isData = false;
vals = [];

line = strtrim(string(line));
lineChar = char(line);

if strlength(line) == 0
    return;
end

sensorToken = regexp(lineChar, '^Sensor\s+(\d+):$', 'tokens', 'once');

if ~isempty(sensorToken)
    currentValidationSensor = str2double(sensorToken{1});

    if verbose
        disp("Skipping non-data line: " + line);
    end

    return;
end

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

line2 = replace(line, ";", ",");
tokens = split(line2, ",");
valsTemp = str2double(tokens).';
NumValsTotal = 1 + NumSens*4;

if numel(valsTemp) == NumValsTotal && ~isnan(valsTemp(1))
    vals = valsTemp;
    isData = true;
elseif verbose
    disp("Skipping non-data line: " + line);
end

end

function cleanupSensorSerial(s)

try
    flush(s);
catch
end

end
