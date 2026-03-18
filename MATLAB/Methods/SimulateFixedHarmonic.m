function [pos,t,name] = SimulateFixedHarmonic(omega,amp,maxT,varargin)
%SIMULATEFIXEDHARMONIC Simulate fixed harmonic signal
% Generates oscillatory signals of 1-N frequencies with different
% amplitude values for a specific time duration.
%
% INPUT:
%   omega   scalar or vector of frequencies in Hz
%   amp     scalar or vector of amplitudes in mm
%   maxT    scalar maximum simulation time in seconds
%   varargin can contain:
%       'nStepsPerSecond', value
%
% OUTPUT:
%   pos     signal position in mm
%   t       time vector
%   name    file name string

    if mod(numel(varargin),2) ~= 0
        error('Check variable input arguments for SimulateFixedHarmonic.');
    end

    % Force numeric scalar/vector form
    omega = double(omega(:).');   % row vector
    amp   = double(amp(:).');     % row vector
    maxT  = double(maxT);

    % Default
    timeStepsPerSecond = 100;

    % Parse optional args
    for i = 1:2:numel(varargin)
        key = varargin{i};
        val = varargin{i+1};

        if isstring(key)
            key = char(key);
        end

        if strcmpi(key,'nStepsPerSecond')
            timeStepsPerSecond = double(val);
        end
    end

    % Validation
    if ~isscalar(maxT) || ~isfinite(maxT) || maxT <= 0
        error('maxT must be a positive finite scalar.');
    end

    if ~isscalar(timeStepsPerSecond) || ~isfinite(timeStepsPerSecond) || timeStepsPerSecond <= 0
        error('nStepsPerSecond must be a positive finite scalar.');
    end

    if isempty(omega) || isempty(amp)
        error('omega and amp must not be empty.');
    end

    if ~(isscalar(amp) || numel(amp) == numel(omega))
        error('amp must be either a scalar or have the same length as omega.');
    end

    if isscalar(amp) && numel(omega) > 1
        amp = repmat(amp, size(omega));
    end

    nOmega = numel(omega);

    % Number of time points
    nPts = max(2, round(timeStepsPerSecond * maxT) + 1);

    % Time vector
    t = linspace(0, maxT, nPts);

    % Position vector
    pos = zeros(1, numel(t));

    for i = 1:nOmega
        pos = pos + amp(i) * sin(omega(i) * 2*pi * t);
    end

    % Name
    omName = 'om_';
    ampName = 'amp_';

    for i = 1:numel(omega)
        omName = [omName num2str(omega(i)) '_']; %#ok<AGROW>
        ampName = [ampName num2str(amp(i)) '_']; %#ok<AGROW>
    end

    name = [omName ampName num2str(maxT) '_' num2str(timeStepsPerSecond)];
end