%% Seperate routine to calibrate and/or test the table

% Table is moved to positive and negative positions based on the initial
% position. This is used to test the steps per mm setting and the general
% functionality of the table without using too complicated signals. 

delimiter = filesep;
rootpath    = [pwd filesep];
addpath(genpath([rootpath 'Methods' filesep])); % Signal generating methods
addpath(genpath([rootpath 'Functions' filesep])); % MATLAB functions
addpath(genpath([rootpath 'Classes' filesep])); % MATLAB classes

if ~exist('dev','var') || ~isa(dev,'internal.Serialport')
    dev = serialport("/dev/ttyUSB0",921600);
    pause(0.1)
    dev.flush
    fprintf(['Number of Bytes available: ', num2str(dev.NumBytesAvailable), '.\n'])
end

calibLength = 5; %% displacement distance [mm]
sPMM = 29.6296; % steps per mm

% instructions per second (basically the speed), note that in this example
% the table needs 5 instructions for one cycle, so a rate of 10 would mean
% two cycles per second.
rate = 10;

nCycles = 5; % number of cycles (0-positive-0-negative-0)

SendInstructionToUSB(dev,'reset')
msg = sprintf('set spmm %f',sPMM);
SendInstructionToUSB(dev,msg)
msg = sprintf('set rate %5.4f',rate);
SendInstructionToUSB(dev,msg)

for i=1:nCycles
    msg = sprintf('add %5.4f',calibLength);
    SendInstructionToUSB(dev,msg)
    msg = sprintf('add %5.4f',0);
    SendInstructionToUSB(dev,msg)
    msg = sprintf('add %5.4f',-calibLength);
    SendInstructionToUSB(dev,msg)
    msg = sprintf('add %5.4f',0);
    SendInstructionToUSB(dev,msg)
end

SendInstructionToUSB(dev,'info')

keyboard; % stop before actual test

%%

SendInstructionToUSB(dev,'start')
SendInstructionToUSB(dev,'info')