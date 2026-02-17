%This is a crude script that shall move the wagon for 1 cm (add 10, line 11)
% check this with a visual mesearuing device, such as a ruler.

SendInstructionToUSB(dev,'reset')
dev.flush
SendInstructionToUSB(dev,'info')
stepsPerMM = 1600/20;
spmmcommand = sprintf('set spmm %5.4f',stepsPerMM);
SendInstructionToUSB(dev,spmmcommand)
SendInstructionToUSB(dev,'info')
SendInstructionToUSB(dev,'set rate 1')
SendInstructionToUSB(dev,'info')
SendInstructionToUSB(dev,'add 10')
SendInstructionToUSB(dev,'start')