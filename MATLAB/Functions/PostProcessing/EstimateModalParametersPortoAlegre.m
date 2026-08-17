function results = EstimateModalParametersPortoAlegre( ...
    time, acceleration, varargin)
% EstimateModalParametersPortoAlegre
%
% Reproduces the output-only FFT peak-picking method implemented in the
% Porto Alegre processing.m reference:
%   - four mean-centered acceleration channels;
%   - rectangular, unpadded FFT;
%   - maximum spectral envelope across the four channels;
%   - 3% relative peak threshold and 15 Hz minimum peak spacing;
%   - cubic-spline refinement over +/-5 Hz using 5000 points;
%   - narrow-band decay damping from structural channel 4.
%
% The analytic-envelope smoothing length is expressed as the physical
% duration represented by 500 samples at the Porto Alegre rate of 600 Hz.
% It therefore equals 500 samples for the reference data and scales to the
% sampling rate of an adapted data set.

parser = inputParser;
parser.FunctionName = mfilename;
addParameter(parser, "RelativePeakLevel", 0.03, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "MinPeakDistanceHz", 15, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "DeltaFInterpHz", 5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "InterpolationPoints", 5000, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 3 && mod(x, 1) == 0);
addParameter(parser, "DampingChannel", 4, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 1 && mod(x, 1) == 0);
addParameter(parser, "DampingStartCycles", 1, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "DampingEndCycles", 30, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "EnvelopeReferenceSamples", 500, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(parser, "EnvelopeReferenceSampleRateHz", 600, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "ComputeDamping", true, ...
    @(x) islogical(x) || isnumeric(x));
addParameter(parser, "MakePlots", false, ...
    @(x) islogical(x) || isnumeric(x));
parse(parser, varargin{:});

relativePeakLevel = parser.Results.RelativePeakLevel;
minPeakDistanceHz = parser.Results.MinPeakDistanceHz;
deltaFInterpHz = parser.Results.DeltaFInterpHz;
interpolationPoints = parser.Results.InterpolationPoints;
dampingChannel = parser.Results.DampingChannel;
dampingStartCycles = parser.Results.DampingStartCycles;
dampingEndCycles = parser.Results.DampingEndCycles;
envelopeReferenceSamples = parser.Results.EnvelopeReferenceSamples;
envelopeReferenceSampleRateHz = ...
    parser.Results.EnvelopeReferenceSampleRateHz;
computeDamping = logical(parser.Results.ComputeDamping);
makePlots = logical(parser.Results.MakePlots);

time = double(time(:));
acceleration = double(acceleration);

if isempty(time) || ~isnumeric(acceleration) || ...
        size(acceleration, 1) ~= numel(time)
    error("Time and acceleration must have the same nonzero row count.");
end

if size(acceleration, 2) ~= 4
    error("The Porto Alegre reference method requires exactly four channels.");
end

if dampingChannel > size(acceleration, 2)
    error("DampingChannel exceeds the number of acceleration channels.");
end

if numel(time) < 64
    error("Too few samples for Porto Alegre FFT processing.");
end

if any(~isfinite(time)) || any(~isfinite(acceleration), "all")
    error("Time and acceleration must contain only finite values.");
end

dt = time(2) - time(1);

if ~isfinite(dt) || dt <= 0 || any(diff(time) <= 0)
    error("Time must be strictly increasing with a positive first interval.");
end

fs = 1 / dt;
measurementDuration = time(end) - time(1);

if ~isfinite(measurementDuration) || measurementDuration <= 0
    error("Measurement duration must be positive.");
end

dfDuration = 1 / measurementDuration;
numberOfSamples = size(acceleration, 1);
numberOfPositiveLines = round(numberOfSamples / 2);

%% -------------------- REFERENCE FFT --------------------
accelerationCentered = acceleration - mean(acceleration, 1);
fftFull = fft(accelerationCentered) / (numberOfSamples / 2);
fftPositive = fftFull(1:numberOfPositiveLines, :);

% MATLAB compares complex values by magnitude and phase. Taking abs after
% max therefore reproduces the reference max(complex spectra) construction.
[envelopeComplex, envelopeChannel] = max(fftPositive, [], 2);
envelopeMagnitude = abs(envelopeComplex);

% This linspace, including fs/2 as its last point, intentionally reproduces
% the reference script rather than replacing it with the canonical DFT axis.
frequencyAxis = linspace( ...
    0, fs / 2, numberOfPositiveLines).';
fftAxisSpacingHz = frequencyAxis(2) - frequencyAxis(1);

maximumEnvelope = max(envelopeMagnitude);

if ~isfinite(maximumEnvelope) || maximumEnvelope <= 0
    error("The spectral envelope is empty or invalid.");
end

minimumPeakDistanceBins = max(1, round( ...
    minPeakDistanceHz / dfDuration));
[peakValues, peakLocations] = findpeaks( ...
    envelopeMagnitude, ...
    "MinPeakHeight", relativePeakLevel * maximumEnvelope, ...
    "MinPeakDistance", minimumPeakDistanceBins);

numberOfPeaks = numel(peakLocations);
frequencyHz = nan(1, numberOfPeaks);
refinedPeakValues = nan(1, numberOfPeaks);
boundaryAdjusted = false(1, numberOfPeaks);
interpolationFrequency = cell(1, numberOfPeaks);
interpolationEnvelope = cell(1, numberOfPeaks);
npt = max(1, round(deltaFInterpHz / dfDuration));

%% -------------------- CUBIC-SPLINE REFINEMENT --------------------
for iPeak = 1:numberOfPeaks
    referenceLeft = peakLocations(iPeak) - npt;
    referenceRight = peakLocations(iPeak) + npt;
    indexLeft = max(referenceLeft, 1);
    indexRight = min(referenceRight, numberOfPositiveLines);
    boundaryAdjusted(iPeak) = ...
        indexLeft ~= referenceLeft || indexRight ~= referenceRight;

    if indexRight <= indexLeft
        frequencyHz(iPeak) = frequencyAxis(peakLocations(iPeak));
        refinedPeakValues(iPeak) = ...
            envelopeMagnitude(peakLocations(iPeak));
        continue;
    end

    localFrequency = linspace( ...
        frequencyAxis(indexLeft), ...
        frequencyAxis(indexRight), ...
        interpolationPoints);
    localEnvelope = spline( ...
        frequencyAxis(indexLeft:indexRight), ...
        envelopeMagnitude(indexLeft:indexRight), ...
        localFrequency);
    [refinedPeakValues(iPeak), maximumIndex] = max(localEnvelope);
    frequencyHz(iPeak) = localFrequency(maximumIndex);
    interpolationFrequency{iPeak} = localFrequency;
    interpolationEnvelope{iPeak} = localEnvelope;
end

%% -------------------- REFERENCE DECAY DAMPING --------------------
dampingRatio = nan(1, numberOfPeaks);
dampingLambda = nan(1, numberOfPeaks);
dampingStatus = repmat("not evaluated", 1, numberOfPeaks);
dampingTime = cell(1, numberOfPeaks);
dampingSignal = cell(1, numberOfPeaks);
dampingEnvelope = cell(1, numberOfPeaks);
dampingFit = cell(1, numberOfPeaks);
envelopeWindowSamples = max(1, round( ...
    envelopeReferenceSamples * fs / envelopeReferenceSampleRateHz));

if computeDamping
    dampingSpectrumReference = fftFull(:, dampingChannel);

    for iPeak = 1:numberOfPeaks
        if ~isfinite(frequencyHz(iPeak)) || frequencyHz(iPeak) <= 0
            dampingStatus(iPeak) = "invalid frequency";
            continue;
        end

        filteredSpectrum = dampingSpectrumReference;
        lowerZeroEnd = peakLocations(iPeak) - npt;
        upperZeroStart = peakLocations(iPeak) + npt;

        if lowerZeroEnd >= 1
            filteredSpectrum(1:min(lowerZeroEnd, numberOfSamples)) = 0;
        end

        if upperZeroStart <= numberOfSamples
            filteredSpectrum(max(upperZeroStart, 1):end) = 0;
        end

        filteredAcceleration = real(ifft( ...
            filteredSpectrum * round(numberOfSamples / 2)));
        [~, peakTimeIndex] = max(filteredAcceleration);
        startOffset = round((dampingStartCycles / frequencyHz(iPeak)) / dt);
        endOffset = round((dampingEndCycles / frequencyHz(iPeak)) / dt);
        fitStart = peakTimeIndex + startOffset;
        fitEnd = peakTimeIndex + endOffset;

        if fitStart < 1 || fitEnd > numberOfSamples || fitEnd <= fitStart
            dampingStatus(iPeak) = "decay interval outside record";
            continue;
        end

        decaySignal = filteredAcceleration(fitStart:fitEnd);
        analyticWindow = envelopeWindowSamples;

        if analyticWindow < 2
            dampingStatus(iPeak) = "decay interval too short";
            continue;
        end

        try
            upperEnvelope = envelope( ...
                decaySignal, analyticWindow, "analytic");
        catch ME
            dampingStatus(iPeak) = "envelope failed: " + string(ME.message);
            continue;
        end

        fitTime = time(fitStart:fitEnd) - time(peakTimeIndex);
        initialEnvelope = upperEnvelope(1);

        if ~isfinite(initialEnvelope) || initialEnvelope <= 0 || ...
                any(~isfinite(upperEnvelope))
            dampingStatus(iPeak) = "invalid analytic envelope";
            continue;
        end

        objective = @(lambda) sum(( ...
            upperEnvelope(:) - initialEnvelope * exp(-lambda * fitTime(:))).^2);
        searchOptions = optimset("Display", "off");
        lambda = fminsearch(objective, 0.001, searchOptions);

        dampingLambda(iPeak) = lambda;
        dampingRatio(iPeak) = lambda / (2 * pi * frequencyHz(iPeak));
        dampingStatus(iPeak) = "estimated";
        dampingTime{iPeak} = time(fitStart:fitEnd);
        dampingSignal{iPeak} = decaySignal;
        dampingEnvelope{iPeak} = upperEnvelope;
        dampingFit{iPeak} = initialEnvelope * exp(-lambda * fitTime);
    end
end

%% -------------------- OPTIONAL REFERENCE-STYLE PLOTS --------------------
if makePlots
    figure("Name", "Porto Alegre style FFT analysis", "Color", "w");
    tiledlayout(2, 1, "TileSpacing", "compact");

    nexttile;
    plot(time, accelerationCentered);
    grid on;
    xlabel("Time [s]");
    ylabel("Acceleration [m/s^2]");
    title("Mean-centered structural responses");

    nexttile;
    plot(frequencyAxis, abs(fftPositive), "LineWidth", 0.8);
    hold on;
    plot(frequencyAxis, envelopeMagnitude, "k", "LineWidth", 1.2);
    plot(frequencyAxis(peakLocations), peakValues, "or");
    grid on;
    xlabel("Frequency [Hz]");
    ylabel("Acceleration spectrum [m/s^2]");
    title("Four-channel FFT envelope and selected peaks");
end

%% -------------------- OUTPUT --------------------
results = struct();
results.method = "Porto Alegre output-only FFT peak picking";
results.time = time;
results.acceleration = acceleration;
results.accelerationCentered = accelerationCentered;
results.fftFull = fftFull;
results.fftPositive = fftPositive;
results.frequencyAxis = frequencyAxis;
results.envelopeComplex = envelopeComplex;
results.envelopeMagnitude = envelopeMagnitude;
results.envelopeChannel = envelopeChannel;
results.peakValues = peakValues;
results.peakLocations = peakLocations;
results.refinedPeakValues = refinedPeakValues;
results.freqHz = frequencyHz;
results.zeta = dampingRatio;
results.dampingLambda = dampingLambda;
results.dampingStatus = dampingStatus;
results.dampingTime = dampingTime;
results.dampingSignal = dampingSignal;
results.dampingEnvelope = dampingEnvelope;
results.dampingFit = dampingFit;
results.interpolationFrequency = interpolationFrequency;
results.interpolationEnvelope = interpolationEnvelope;
results.boundaryAdjusted = boundaryAdjusted;
results.fs = fs;
results.dt = dt;
results.measurementDuration = measurementDuration;
results.dfDuration = dfDuration;
results.fftAxisSpacingHz = fftAxisSpacingHz;
results.numberOfSamples = numberOfSamples;
results.numberOfPeaks = numberOfPeaks;
results.settings = struct( ...
    "relativePeakLevel", relativePeakLevel, ...
    "minPeakDistanceHz", minPeakDistanceHz, ...
    "deltaFInterpHz", deltaFInterpHz, ...
    "interpolationMethod", "spline", ...
    "interpolationPoints", interpolationPoints, ...
    "spectrumWindow", "rectangular", ...
    "zeroPadding", false, ...
    "dampingChannel", dampingChannel, ...
    "dampingStartCycles", dampingStartCycles, ...
    "dampingEndCycles", dampingEndCycles, ...
    "envelopeReferenceSamples", envelopeReferenceSamples, ...
    "envelopeReferenceSampleRateHz", envelopeReferenceSampleRateHz, ...
    "envelopeWindowSamplesUsed", envelopeWindowSamples);

end
