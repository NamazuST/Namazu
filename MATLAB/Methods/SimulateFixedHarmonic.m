function [pos,t,name] = SimulateFixedHarmonic(omega,amp,maxT,varargin)
%SIMULATEFIXEDHARMONICS Simulate Fixed Harmonic Signal
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
    for i=1:2:length(varargin)
        if strcmp(varargin{i},'nStepsPerSecond')
            timeStepsPerSecond = varargin{i+1};
        end
    end
    nOmega = length(omega);
    %"time" space
    t = linspace(0,maxT,timeStepsPerSecond*maxT);

    dt = t(2)-t(1);
    pos = zeros(1,length(t));
    
    for i=1:nOmega
        pos = pos + amp(i)*sin(omega(i)*2*pi*t);
    end

    omName = 'om_';
    ampName = 'amp_';

    for i=1:length(omega)
        omName = [omName num2str(omega(i)) '_'];
        ampName = [ampName num2str(amp(i)) '_'];
    end
    name = [omName ampName num2str(maxT) '_' num2str(timeStepsPerSecond)];

end

