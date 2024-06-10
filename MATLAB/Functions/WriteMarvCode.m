function [shakingData] = WriteMarvCode(shakingData)

    % Compiling marv code from positions and saving to the shakingData format
    
    % Calculation for steps per mm, i.e. microstep setting divided by
    % table's movement per revolution
    % driver is set to 1600 steps per mm, current table has 54 mm/rev:
    stepsPerMM = 1600/54; % specific for the motor, CHANGE IF TABLE OR MICROSTEPPING IS CHANGED
    % on NEMA 23 (1.8° per step)
    
    form = 'add %5.4f\n';
    
    fileHeader = sprintf('reset\nset spmm %5.4f\nset rate %5.4f\n',stepsPerMM,shakingData.motorRate);
    cmd = fileHeader;
    pos = shakingData.inputSignal(:,2);
    
    for i=1:length(pos)
        cmd = append(cmd,sprintf(form,pos(i)));
    end
    
    shakingData.marvCode = cmd;
    
end

