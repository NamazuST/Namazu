function [currentSimulationData] = StartExperimentSerial(currentSimulationData,dev)

    portList = serialportlist("available");
    port = 'COM3';

    if exist("a",'var')
        if class(a)=="internal.Serialport"
            disp("Arduino found on port!");
        end
    elseif sum(port==portList)==0
        error('Port not found/open or port is in use, check USB connection!')
    else
        a = serialport(port,115200);
    end

    sampleRate = 100;
    dt = 1/sampleRate;
    samplesPerRead = sampleRate;
   
    data1 = [];
    data2 = [];
    data = "";

    % java -cp UniversalGcodeSender.jar com.willwinder.ugs.cli.TerminalClient --controller GRBL --port COM5 --baud 115200 --print-progressbar --file test.gcode
    
    times = [];
    tic;
    flush(a);
    SendInstructionToUSB(dev,'start',1);
    while(toc <= currentSimulationData.inputSignal(end,1))
        
        if a.NumBytesAvailable > 0
            data = append(data,readline(a));
            times(end+1) = toc;
        end
        
    end
    
    toc
    eltime = toc;
    
    dat = splitlines(data);
    dat(1:2) = [];
    dat(end) = [];
    dat = split(dat,{',',':'});
    dat = double(dat(:,2:2:end));
    
    data1 = dat(:,1:3);
    data2 = dat(:,4:6);
    
    currentSimulationData.dataPlate = data2;
    currentSimulationData.dataObject = data1;
    currentSimulationData.sampleRate = sampleRate;
    
    save(currentSimulationData.fileName,'currentSimulationData');

end


