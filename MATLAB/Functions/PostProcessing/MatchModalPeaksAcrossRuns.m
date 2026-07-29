function [freqMatrixHz, zetaMatrix, modeInfo] = MatchModalPeaksAcrossRuns( ...
    freqCells, zetaCells, varargin)
% MatchModalPeaksAcrossRuns
%
% Matches repeated modal peaks by frequency before calculating batch
% statistics. A mode is retained only when it occurs in the configured
% fraction of runs.

parser = inputParser;
parser.FunctionName = mfilename;
addParameter(parser, "ToleranceHz", 3, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(parser, "MinOccurrenceFraction", 0.5, ...
    @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
addParameter(parser, "IncludedRuns", [], ...
    @(x) isempty(x) || (isvector(x) && ...
        (islogical(x) || (isnumeric(x) && all(isfinite(x)) && ...
        all(x == 0 | x == 1)))));
parse(parser, varargin{:});

if ~iscell(freqCells) || ~iscell(zetaCells) || numel(freqCells) ~= numel(zetaCells)
    error("freqCells and zetaCells must be cell arrays with equal size.");
end

nRuns = numel(freqCells);
toleranceHz = parser.Results.ToleranceHz;
includedRuns = parser.Results.IncludedRuns;

if isempty(includedRuns)
    includedRuns = true(nRuns, 1);
else
    if numel(includedRuns) ~= nRuns
        error("IncludedRuns must contain one element per run.");
    end

    includedRuns = logical(includedRuns(:));
end

nIncludedRuns = nnz(includedRuns);
minimumOccurrenceCount = max(1, ...
    ceil(parser.Results.MinOccurrenceFraction * nIncludedRuns));

allFrequency = zeros(0, 1);
allRun = zeros(0, 1);
allPeak = zeros(0, 1);

for iRun = 1:nRuns
    if ~includedRuns(iRun)
        continue;
    end

    frequencies = double(freqCells{iRun}(:));
    valid = isfinite(frequencies);
    peakIndices = find(valid);
    allFrequency = [allFrequency; frequencies(valid)]; %#ok<AGROW>
    allRun = [allRun; repmat(iRun, nnz(valid), 1)]; %#ok<AGROW>
    allPeak = [allPeak; peakIndices]; %#ok<AGROW>
end

emptyModeInfo = table( ...
    Size=[0, 6], ...
    VariableTypes=repmat("double", 1, 6), ...
    VariableNames=[ ...
        "Mode", ...
        "CenterHz", ...
        "OccurrenceCount", ...
        "OccurrenceFraction", ...
        "MinHz", ...
        "MaxHz"]);

if isempty(allFrequency)
    freqMatrixHz = nan(nRuns, 0);
    zetaMatrix = nan(nRuns, 0);
    modeInfo = emptyModeInfo;
    return;
end

[allFrequency, order] = sort(allFrequency);
allRun = allRun(order);
allPeak = allPeak(order);

clusterId = zeros(size(allFrequency));
clusterCount = 0;
clusterValues = cell(0, 1);

for iValue = 1:numel(allFrequency)
    assignedCluster = 0;
    smallestDistance = inf;

    for iCluster = 1:clusterCount
        center = median(clusterValues{iCluster});
        distance = abs(allFrequency(iValue) - center);

        if distance <= toleranceHz && distance < smallestDistance
            assignedCluster = iCluster;
            smallestDistance = distance;
        end
    end

    if assignedCluster == 0
        clusterCount = clusterCount + 1;
        assignedCluster = clusterCount;
        clusterValues{assignedCluster, 1} = allFrequency(iValue);
    else
        clusterValues{assignedCluster}(end + 1, 1) = allFrequency(iValue);
    end

    clusterId(iValue) = assignedCluster;
end

candidate = repmat(struct( ...
    "center", NaN, ...
    "occurrenceCount", 0, ...
    "minHz", NaN, ...
    "maxHz", NaN, ...
    "indices", []), clusterCount, 1);

for iCluster = 1:clusterCount
    indices = find(clusterId == iCluster);
    values = allFrequency(indices);
    candidate(iCluster).center = median(values);
    candidate(iCluster).occurrenceCount = numel(unique(allRun(indices)));
    candidate(iCluster).minHz = min(values);
    candidate(iCluster).maxHz = max(values);
    candidate(iCluster).indices = indices;
end

keep = [candidate.occurrenceCount] >= minimumOccurrenceCount;
candidate = candidate(keep);

if isempty(candidate)
    freqMatrixHz = nan(nRuns, 0);
    zetaMatrix = nan(nRuns, 0);
    modeInfo = emptyModeInfo;
    return;
end

[~, modeOrder] = sort([candidate.center]);
candidate = candidate(modeOrder);
nModes = numel(candidate);

freqMatrixHz = nan(nRuns, nModes);
zetaMatrix = nan(nRuns, nModes);
Mode = (1:nModes).';
CenterHz = nan(nModes, 1);
OccurrenceCount = zeros(nModes, 1);
OccurrenceFraction = zeros(nModes, 1);
MinHz = nan(nModes, 1);
MaxHz = nan(nModes, 1);

for iMode = 1:nModes
    CenterHz(iMode) = candidate(iMode).center;
    MinHz(iMode) = candidate(iMode).minHz;
    MaxHz(iMode) = candidate(iMode).maxHz;
    indices = candidate(iMode).indices;

    for iRun = 1:nRuns
        runIndices = indices(allRun(indices) == iRun);

        if isempty(runIndices)
            continue;
        end

        [~, nearestIndex] = min(abs( ...
            allFrequency(runIndices) - candidate(iMode).center));
        selectedIndex = runIndices(nearestIndex);
        peakIndex = allPeak(selectedIndex);
        freqMatrixHz(iRun, iMode) = allFrequency(selectedIndex);

        runZeta = double(zetaCells{iRun}(:));
        if peakIndex <= numel(runZeta) && isfinite(runZeta(peakIndex))
            zetaMatrix(iRun, iMode) = runZeta(peakIndex);
        end
    end

    OccurrenceCount(iMode) = nnz(isfinite(freqMatrixHz(:, iMode)));
    OccurrenceFraction(iMode) = ...
        OccurrenceCount(iMode) / max(nIncludedRuns, 1);
end

modeInfo = table( ...
    Mode, ...
    CenterHz, ...
    OccurrenceCount, ...
    OccurrenceFraction, ...
    MinHz, ...
    MaxHz);

end
