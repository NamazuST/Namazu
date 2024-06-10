function [] = WriteGCode(amplitude,t,fname,plotBool)

    formatSpec = 'G01G21G90X%3.2fF%3.2f\n';
    
    dt = t(2)-t(1);
    
    if max(abs(amplitude))>5
        warning("amplitude >5, maximum amplitude is %3.2f",max(abs(amplitude)));
    else
        fprintf("maximum amplitude is %3.2f\n",max(abs(amplitude)));
    end

    %since we have negative locations/amplitudes no negative speed is necessary
    speed = abs(diff(amplitude))/dt;
    %we always start with 0 "displacement" therefore first speed value is also
    %0
    speed(2:end+1) = speed;
    speed(1) = 0;
    
    speed_scale = 60; %weil mm/s, feed rate wird in mm/min angegeben
    speed = speed*speed_scale;

    if max(abs(speed))>5000
        warning("speed >5000, maximum speed is %3.2f",max(abs(speed)));
    else
        fprintf("maximum speed is %3.2f\n",max(abs(speed)));
    end
    
    if plotBool
        figure;
        subplot(2,1,1);
        plot(t,amplitude);
        xlabel("time [s]");ylabel("amplitude [mm]");
        subplot(2,1,2);
        plot(t,speed);
        xlabel("time [s]");ylabel("schbeeeeed [mm/s]");
    end

    % s.flush
    line = [];
    % s.writeline("G90");

    fileID = fopen(fname,"W");
    % fprintf(fileID,"G21G90\n");

    fprintf(fileID,sprintf(formatSpec,amplitude(1),100));
    fprintf(fileID,"G4P2\n");

    for i=2:length(t)
        if speed(i)<0.1
            speed_ = .1;
        else
            speed_ = speed(i);
        end
        cmd{i} = sprintf(formatSpec,amplitude(i),speed_);
        fprintf(fileID,cmd{i});

    %     line = s.readline();
    %     str1 = strfind(line, "Error");
    %     str2 = strfind(line, "error");
    %     if str2>0
    %         warning("error");
    %     end

    end

    % fprintf(fileID,"G21G90X0F100\n");

    fclose(fileID);
end

