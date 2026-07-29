function [pos, t, name] = SimulateFrequencySweep(maxF, maxA, maxT, varargin)
% SimulateFrequencySweep
%
% Generates a displacement-controlled frequency sweep.
%
% Inputs:
%   maxF  maximum angular frequency [rad/s]
%   maxA  displacement amplitude [mm]
%   maxT  duration [s]
%
% Name-value options:
%   "nStepsPerSecond"   command rate [Hz], default 100
%   "frequencyFunction" function handle omega(t) [rad/s]. The default is
%                       a linear sweep from 0 to maxF.
%
% Outputs are row vectors for compatibility with the existing NAMAZU
% signal-generator functions.
%
% The phase is the time integral of angular frequency. The previous
% implementation used sin(omega(t)*t), which made a nominal linear sweep
% finish at twice the requested instantaneous frequency.

parser = inputParser;
parser.FunctionName = mfilename;
addParameter(parser, "nStepsPerSecond", 100, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
addParameter(parser, "frequencyFunction", [], ...
    @(x) isempty(x) || isa(x, "function_handle"));
parse(parser, varargin{:});

validateattributes(maxF, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'}, mfilename, 'maxF');
validateattributes(maxA, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'}, mfilename, 'maxA');
validateattributes(maxT, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'}, mfilename, 'maxT');

timeStepsPerSecond = parser.Results.nStepsPerSecond;
nIntervals = max(1, round(maxT * timeStepsPerSecond));
t = linspace(0, maxT, nIntervals + 1);

if isempty(parser.Results.frequencyFunction)
    omega = maxF * t / maxT;
else
    omega = parser.Results.frequencyFunction(t);

    if isscalar(omega)
        omega = repmat(omega, size(t));
    end

    if ~isnumeric(omega) || ~isequal(size(omega), size(t)) || ...
            any(~isfinite(omega), "all") || any(omega < 0, "all")
        error("frequencyFunction must return one finite, nonnegative angular frequency per time sample.");
    end
end

phase = cumtrapz(t, omega);
pos = maxA .* sin(phase);

name = sprintf("%.6gHz_%.6gs", maxF/(2*pi), maxT);

end
