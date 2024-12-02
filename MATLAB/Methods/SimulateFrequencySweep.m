function [pos,t,name] = SimulateFrequencySweep(maxF,maxA,maxT,varargin)
    %SIMULATEFREQUENCYSWEEP Simulate a sweep from 0 Hz to a defined maximum
    %frequency
%   Generates oscillatory signals of 1-N frequencies with different
%   amplitude values for a specific time duration.
%INPUT:
%   omega:  scalar value of a frequency or an array of several overlapping
%   frequencies in HZ
%   amp:    Amplitude factor in mm for the respective frequency, scalar or array
%   maxT:   scalar value of the maximum simulation time in seconds
%   varargin: can contain a manually chosen 'nStepsPerSecond' 
%   number of timeStepsPerSecond
%   the default value is 100.
%
% OUTPUT:
%   pos: signal position in mm
%   t: Specific time discretisation suited to the signal
%   name: File name

    if mod(length(varargin),2) ~= 0
        error("check variable input arguments for SimulateRandomHarmonic");
    end
    
    timeStepsPerSecond = 100; % time discretisation
    freqFunc = @(t) t/maxT * maxF;
    for i=1:2:length(varargin)
        if strcmp(varargin{i},'nStepsPerSecond')
            timeStepsPerSecond = varargin{i+1};
        end
        if strcmp(varargin{i},'frequencyFunction')
            freqFunc = varargin{i+1};
        end
    end

    t = linspace(0,maxT,maxT*timeStepsPerSecond);
    posFunc = @(t) maxA.*sin(freqFunc(t).*t);

    pos = posFunc(t);

    name = [num2str(maxF) 'Hz_' num2str(maxT) 's'];
end

