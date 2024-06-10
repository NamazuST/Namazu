function [ret] = SendInstructionToUSB(dev,msg)
    writeline(dev,msg);
    ret = "";
    while ret == ""
        while dev.NumBytesAvailable > 0
            ret = append(ret,dev.readline);
            ret = append(ret,newline);
            pause(0.005)
        end
    end
end

