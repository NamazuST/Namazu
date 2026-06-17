clc; clear;
%Starting
fprintf('[%s]: ', datetime("now"))
fprintf('Starting %s. \n ',mfilename)

%% Path Dependencies
% Root Path
delimiter = filesep;
rootpath    = [pwd filesep];
addpath(genpath([rootpath 'Methods' filesep])); % Signal generating methods
addpath(genpath([rootpath 'Functions' filesep])); % MATLAB functions
addpath(genpath([rootpath 'Classes' filesep])); % MATLAB classes

%Set default plot text interpreter to latex
set(0,'defaulttextinterpreter','latex')
set(0,'defaultAxesFontSize',12)

%% Start the Live Monitor

state = LiveSingleSensorFFTMonitor( ...
    "Port", "COM9", ...
    "Baud", 1000000, ...
    "Direction", "y", ...
    "NominalSampleRate", 500, ...
    "SerialTimeout", 3.0, ...
    "FFTWindowSeconds", 10, ...
    "FMax", 100, ...
    "MaxPeaks", 4);