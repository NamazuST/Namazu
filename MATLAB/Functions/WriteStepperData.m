function [shakingData] = WriteStepperData(shakingData,varargin)
    %%WRITESTEPPERDATA Function to format simulated displacement into data
    %%readable by the stepper driver
    
    stepsPerMM = 2*38; % SWITCHED TO 3200 steps/rev!!! 24.04.2023
    rate = 100;
    fname = 0;
    form = 'add %3.2f\n';
    dev = 0;
    
    if mod(length(varargin),2)==0
        for i=1:length(varargin)
            if strcmp(varargin{i},'SPMM')
                stepsPerMM = varargin{i+1};
            elseif strcmp(varargin{i},'rate')
                rate = varargin{i+1};
            elseif strcmp(varargin{i},'fname')
                fname = varargin{i+1};
            elseif strcmp(varargin{i},'sendToUSB')
                dev = varargin{i+1};
            elseif strcmp(varargin{i},'baud')
                baud = varargin{i+1};
            end
        end
    end

    fileHeader = sprintf('reset\nset spmm %i\nset rate %3.1f\n',stepsPerMM,rate);
    cmd = fileHeader;
    
    for i=1:length(pos)
        cmd = append(cmd,sprintf(form,pos(i)));
    end
    
    if isa(fname,'String')
        fileID = fopen(fname,"W");
        fprintf(fileID,cmd);
        fclose(fileID);
    end
    
    if isa(dev,'internal.Serialport') || isa(dev,'char') || isa(dev,'string')
        [succ,dev] = SendToUSB(cmd,dev);
    end
    
end

