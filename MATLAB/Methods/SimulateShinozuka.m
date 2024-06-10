function [pos, t, name] = SimulateShinozuka(PSD, tEnd, maxS, nOmega, varargin)
%SIMULATESHINOZUKA
%   Generates a gaussian process by the Spectral Representation Method
%   as signal in the variable pos which has specific
%   features according to the pbulication 1991 Shinozuka & Deodatis -
%   Simulation of Stochastic Processes by Spectral Representation
% OUTPUT:
%   pos: Gaussian process with specific features according to Shinozuka and
%   Deodatis
%   time: Specific time discretisation suited to the process
%   name: File name

if mod(length(varargin),2) ~= 0
    error('')
end

timeStepsPerSecond = 100; % time discretisation, why 108?
for i=1:2:length(varargin)
    if strcmp(varargin{i},'nStepsPerSecond')
        timeStepsPerSecond = varargin{i+1};
    end
end

t = linspace(0,tEnd,tEnd*timeStepsPerSecond);
pos = simulateStochProcess(PSD,maxS,t,nOmega,1);

name = 'Shinozuka';

end