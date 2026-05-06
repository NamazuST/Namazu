%This is a crude script that shall move the wagon for 1 cm (add 10, line 11)
% check this with a visual mesearuing device, such as a ruler.

dev = serialport("COM4",921600);
pause(0.1)
dev.flush
fprintf(['Number of Bytes available: ', num2str(dev.NumBytesAvailable), '.\n'])

SendInstructionToUSB(dev,'reset')
dev.flush
SendInstructionToUSB(dev,'info')
%stepsPerMM = 1600/54; %Mk2
stepsPerMM = 1600/20; %Mk3
spmmcommand = sprintf('set spmm %5.4f',stepsPerMM);
SendInstructionToUSB(dev,spmmcommand)
SendInstructionToUSB(dev,'info')
SendInstructionToUSB(dev,'set rate 1')
SendInstructionToUSB(dev,'info')
SendInstructionToUSB(dev,'add -10')
SendInstructionToUSB(dev,'start')