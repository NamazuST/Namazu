function [shakingData] = SendDataToMotor(shakingData,dev)

    cmd = shakingData.marvCode;

    if isa(dev,'internal.Serialport') || isa(dev,'char') || isa(dev,'string')
        [succ,dev] = SendToUSB(cmd,dev);
    else
        error("Device not found!");
    end

end

