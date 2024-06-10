%This is a crude script that shall move the wagon for 1 cm, check this with
%a visual mesearuing device, such as a ruler.

SendInstructionToUSB(dev,'reset',1)
dev.flush
SendInstructionToUSB(dev,'info',1)
SendInstructionToUSB(dev,'set spmm 29.6296',1)
SendInstructionToUSB(dev,'info',1)
SendInstructionToUSB(dev,'set rate 1',1)
SendInstructionToUSB(dev,'info',1)
SendInstructionToUSB(dev,'add 10',1)
SendInstructionToUSB(dev,'start',1)