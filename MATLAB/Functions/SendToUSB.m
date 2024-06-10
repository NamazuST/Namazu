%% function to send multiple commands to serial device

function [succ,dev] = SendToUSB(cmd,dev)

    succ = 1;

    displayInterval = 0.1;

    %number of commands to send at once. Can accelerate the sending
    %process, but too many commands make the connection unstable
    nSimultaneous = 10;
    
    if ~isa(dev,'internal.Serialport')
        error("Specified device is not a Serial port!");
    end
    
    chararr = splitlines(cmd);
    chararr(end) = []; % throw away last
    nCommandsTotal = length(chararr);
    cmdNumber = 0;
    currentDone = displayInterval;
    
    try
        while length(chararr)>1
            cmdNumber = cmdNumber + 1;
            lCmd = min(nSimultaneous,length(chararr)); %length of command
            toSend = "";
            for i=1:lCmd
                toSend = append(toSend,chararr{i});
                if ~(i==lCmd)
                    toSend = append(toSend,newline);
                end
            end
            repl = SendInstructionToUSB(dev,toSend);
            if ~(length(strfind(repl,"OK:"))==lCmd)
                error("ShakingTable:FailedToSendToUSB","Failed to send to USB");
            end
            chararr(1:lCmd) = [];
            pctDone = (1-length(chararr)/nCommandsTotal);
            if pctDone>currentDone
                currentDone = currentDone + displayInterval;
                fprintf("%2.0d %%\n",round(pctDone*100));
            end
        end
    catch ME
        if strcmp(ME.identifier,"ShakingTable:FailedToSendToUSB")
            warning(append("Failed to send to USB after sending command number ",...
                num2str(cmdNumber), ": ", chararr{1},...
                ", resetting controller."));
            while dev.NumBytesAvailable>0
                repl = append(repl,readline(dev));
            end
            disp(append("Error message: ", repl));
            SendInstructionToUSB(dev,'reset')
            SendInstructionToUSB(dev,'info')
            succ = 0;
        else
            rethrow(ME);
        end
    end
    fprintf("%2.0d %%\n",100);
    flush(dev);
    SendInstructionToUSB(dev,'info')

end

