function [pos, t, dt, maxT, name] = SimulateShinozukaBenchmark(varargin)
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

if length(varargin) > 1
    error("check variable input arguments for SimulateShinozukaBenchmark");
else
    amplitude_scaling_factor = varargin{1};
    warning(['Shinozuka Benchmark is scaled by a factor of ', num2str(amplitude_scaling_factor)])
end    

%% Parameter Shinozuka example (Shinozuka & Deodatis 1991)
wl = 0; %Starting frequency
wu = 4*pi; %Cutoff frequency
maxT = 64; %Maximum time
% dt = pi/wu; %Time incremet (delta T)
dt = pi/wu;
%M = 128; %Number of Random Phase Angles
dw = 2*pi/maxT; %Omega increment (delta Omega)

t = 0:dt:maxT-dt; %Time discretisation

w = wl:dw:wu-dw; %Omega discretisation

%Continous Power Spectral Density (PSD) related Parameters
sigma = 1; %Standard deviation of in the end, generated signal
b = 1;

S_function = @(omega) 0.25.*sigma^2.*b^3.*omega.^2.*exp(-b*abs(omega));

%% Shinozuka

%Signal generation - omega w determines the number of random phase angles
pos = SpectralRepresentationMethod(S_function, w, t);

%Crude scaling of the signal
pos = pos.*amplitude_scaling_factor;

%PSD estimation using FFT
p_shnzk = StationaryPSD(pos, t);

name = ['scale_', num2str(amplitude_scaling_factor)];

end