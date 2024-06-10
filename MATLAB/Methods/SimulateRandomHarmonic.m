function [pos,t,name] = SimulateRandomHarmonic(omegaBase,ampBase,nOmega,maxT,varargin)
%% SIMULATERANDOMHARMONIC Simulate random harmonic based on input
% omegaBase: basic frequency in Hz
% ampBase: basic amplitude in mm
% nOmega: number of simulated frequecies
% maxT: maximum simulated time

    if mod(length(varargin),2) ~= 0
        error("check variable input arguments for SimulateRandomHarmonic");
    end
    
    timeStepsPerSecond = 108; % time discretisation, why 108?
    for i=1:2:length(varargin)
        if strcmp(varargin{i},'nStepsPerSecond')
            timeStepsPerSecond = varargin{i+1};
        end
    end

    maxTime = maxT; %s
    %"time" space
    t = linspace(0,maxTime,timeStepsPerSecond*maxTime);
    
    omega = 2*rand(1,nOmega)*omegaBase;
    amps = 1+rand(1,nOmega)*(ampBase-1);
    
    dt = t(2)-t(1);
    pos = zeros(1,length(t));
    
    for i=1:nOmega
        pos = pos + amps(i)*sin(omega(i)*2*pi*t);
    end

    name = [num2str(omegaBase) '_' num2str(ampBase) '_' num2str(nOmega) '_' num2str(maxT) '_' num2str(timeStepsPerSecond)];

end

