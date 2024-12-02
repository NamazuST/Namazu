function [pos,t,name] = SimulateImpact(maxD,impactTime,varargin)
%SIMULATEIMPACT Summary of this function goes here
%   Detailed explanation goes here
    
    if mod(length(varargin),2) ~= 0
        error("check variable input arguments for SimulateRandomHarmonic");
    end
    
    timeStepsPerSecond = 100; % time discretisation
    for i=1:2:length(varargin)
        if strcmp(varargin{i},'nStepsPerSecond')
            timeStepsPerSecond = varargin{i+1};
        end
    end

    t = linspace(0,impactTime,impactTime*timeStepsPerSecond);
    pos = linspace(0,maxD,length(t));
    name = [num2str(maxD) 'mm_' num2str(impactTime) 's'];

end

