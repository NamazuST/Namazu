function summary = SummarizeShakeTableFRFRuns( ...
    frfCells, qualityUsableRunMask, varargin)
% SummarizeShakeTableFRFRuns
%
% Builds the cross-run modal summary without acquiring new measurements.
% Only runs that passed acquisition quality control and completed FRF
% analysis contribute to occurrence fractions and modal statistics.

parser = inputParser;
parser.FunctionName = mfilename;
addParameter(parser, "NumSensors", 5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 1 && mod(x, 1) == 0);
addParameter(parser, "ModeMatchToleranceHz", 0.5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "MinModeOccurrenceFraction", 0.8, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(parser, "ReferenceFrequenciesHz", [], ...
    @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x > 0)));
addParameter(parser, "StartFrequencyHz", 0, ...
    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(parser, "EndFrequencyHz", inf, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "ReferenceMatchToleranceHz", 1, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
parse(parser, varargin{:});

if ~iscell(frfCells)
    error("frfCells must be a cell array.");
end

nRuns = numel(frfCells);

if numel(qualityUsableRunMask) ~= nRuns
    error("qualityUsableRunMask must contain one element per run.");
end

qualityUsableRunMask = logical(qualityUsableRunMask(:));
analysisAvailableRunMask = false(nRuns, 1);
frequencyCells = cell(nRuns, 1);
zetaCells = cell(nRuns, 1);

for iRun = 1:nRuns
    frf = frfCells{iRun};

    if isempty(frf) || ~isstruct(frf) || ~isfield(frf, "freqHz")
        continue;
    end

    analysisAvailableRunMask(iRun) = true;

    if ~qualityUsableRunMask(iRun)
        continue;
    end

    frequencyCells{iRun} = frf.freqHz;

    if isfield(frf, "zeta")
        zetaCells{iRun} = frf.zeta;
    else
        zetaCells{iRun} = nan(size(frf.freqHz));
    end
end

includedRunMask = qualityUsableRunMask & analysisAvailableRunMask;

[freqMatrixHz, zetaMatrix, modeInfo] = ...
    MatchModalPeaksAcrossRuns(frequencyCells, zetaCells, ...
        "ToleranceHz", parser.Results.ModeMatchToleranceHz, ...
        "MinOccurrenceFraction", ...
            parser.Results.MinModeOccurrenceFraction, ...
        "IncludedRuns", includedRunMask);

nModes = size(freqMatrixHz, 2);

if height(modeInfo) ~= nModes
    error("Modal summary row count does not match the frequency matrix.");
end

summary = struct();
summary.qualityUsableRunMask = qualityUsableRunMask;
summary.analysisAvailableRunMask = analysisAvailableRunMask;
summary.includedRunMask = includedRunMask;
summary.numRequestedRuns = nRuns;
summary.numQualityUsableRuns = nnz(qualityUsableRunMask);
summary.numIncludedRuns = nnz(includedRunMask);
summary.freqMatrixHz = freqMatrixHz;
summary.zetaMatrix = zetaMatrix;
summary.modeInfo = modeInfo;

if nModes == 0
    summary.freqMeanHz = zeros(1, 0);
    summary.freqStdHz = zeros(1, 0);
    summary.zetaMean = zeros(1, 0);
    summary.zetaStd = zeros(1, 0);
else
    summary.freqMeanHz = mean(freqMatrixHz, 1, "omitnan");
    summary.freqStdHz = std(freqMatrixHz, 0, 1, "omitnan");
    summary.zetaMean = mean(zetaMatrix, 1, "omitnan");
    summary.zetaStd = std(zetaMatrix, 0, 1, "omitnan");
end

[summary.modeShapeRunsNormalizedComplex, ...
    summary.modeShapeMeanNormalizedComplex] = aggregateModeShapes( ...
        frfCells, freqMatrixHz, parser.Results.NumSensors);
summary.modeShapeMeanAmplitude = ...
    abs(summary.modeShapeMeanNormalizedComplex);
summary.modeShapeMeanPhaseDeg = ...
    rad2deg(angle(summary.modeShapeMeanNormalizedComplex));

if height(summary.modeInfo) > 0
    summary.modeInfo.MeanHz = summary.freqMeanHz(:);
    summary.modeInfo.StdHz = summary.freqStdHz(:);
    summary.modeInfo.MeanZeta = summary.zetaMean(:);
    summary.modeInfo.StdZeta = summary.zetaStd(:);
end

summary.referenceComparison = compareReferenceFrequencies( ...
    parser.Results.ReferenceFrequenciesHz, ...
    summary.freqMeanHz, ...
    parser.Results.StartFrequencyHz, ...
    parser.Results.EndFrequencyHz, ...
    parser.Results.ReferenceMatchToleranceHz);

end

function [shapeRuns, shapeMean] = aggregateModeShapes( ...
    frfCells, frequencyMatrixHz, numSensors)

nRuns = numel(frfCells);
nModes = size(frequencyMatrixHz, 2);
shapeRuns = complex(nan(numSensors, nModes, nRuns));

if nModes == 0
    shapeMean = complex(nan(numSensors, 0));
    return;
end

for iRun = 1:nRuns
    frf = frfCells{iRun};

    if isempty(frf) || ~isstruct(frf) || ...
            ~isfield(frf, "freqHz") || ...
            ~isfield(frf, "modeShapeNormalizedComplex")
        continue;
    end

    for iMode = 1:nModes
        targetFrequency = frequencyMatrixHz(iRun, iMode);

        if ~isfinite(targetFrequency)
            continue;
        end

        [distance, peakIndex] = min(abs(frf.freqHz - targetFrequency));

        if isfinite(distance) && peakIndex <= ...
                size(frf.modeShapeNormalizedComplex, 2)
            shapeRuns(:, iMode, iRun) = ...
                frf.modeShapeNormalizedComplex(:, peakIndex);
        end
    end
end

shapeMean = mean(shapeRuns, 3, "omitnan");

for iMode = 1:nModes
    shape = shapeMean(:, iMode);
    [scale, referenceIndex] = max(abs(shape), [], "omitnan");

    if isfinite(scale) && scale > 0
        shapeMean(:, iMode) = ...
            shape * exp(-1i * angle(shape(referenceIndex))) / scale;
    end
end

end

function comparison = compareReferenceFrequencies( ...
    referenceFrequenciesHz, estimatedFrequenciesHz, ...
    analysisMinimumHz, analysisMaximumHz, toleranceHz)

ReferenceHz = double(referenceFrequenciesHz(:));

if isempty(ReferenceHz)
    comparison = table();
    return;
end

InAnalysisBand = ReferenceHz >= analysisMinimumHz & ...
    ReferenceHz <= analysisMaximumHz;
NearestEstimatedHz = nan(size(ReferenceHz));
ErrorHz = nan(size(ReferenceHz));
MatchedWithinTolerance = false(size(ReferenceHz));
estimatedFrequenciesHz = double(estimatedFrequenciesHz(:));
estimatedFrequenciesHz = ...
    estimatedFrequenciesHz(isfinite(estimatedFrequenciesHz));

for iReference = 1:numel(ReferenceHz)
    if ~InAnalysisBand(iReference) || isempty(estimatedFrequenciesHz)
        continue;
    end

    [absoluteError, nearestIndex] = min(abs( ...
        estimatedFrequenciesHz - ReferenceHz(iReference)));
    NearestEstimatedHz(iReference) = estimatedFrequenciesHz(nearestIndex);
    ErrorHz(iReference) = ...
        NearestEstimatedHz(iReference) - ReferenceHz(iReference);
    MatchedWithinTolerance(iReference) = absoluteError <= toleranceHz;
end

comparison = table( ...
    ReferenceHz, ...
    InAnalysisBand, ...
    NearestEstimatedHz, ...
    ErrorHz, ...
    MatchedWithinTolerance);

end
