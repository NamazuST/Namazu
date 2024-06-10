%Connection to nano controller for stepper motor to send gcode
% s = serialport("COM3",115200)
%Gcode string format
close all;clear;

maxTime = 20; %s
timeStepsPerSecond = 108; % time discretisation, why 108?
%"time" space
t = linspace(0,maxTime,timeStepsPerSecond*maxTime);

omegaBase = 2; %basic frequency
ampBase = 2; %basic amplitude (MUST BE >1)
if ampBase<1
    error("Basic amplitude < 1");
end
nOmega = 5; %number of frequencies

omega = 2*rand(1,nOmega)*omegaBase;
amps = 1+rand(1,nOmega)*(ampBase-1);

dt = t(2)-t(1);
amplitude = zeros(1,timeStepsPerSecond*maxTime);

for i=1:nOmega
    amplitude = amplitude + amps(i)*sin(omega(i)*2*pi*t);
end

save("lastSimulation")

% amplitude = 4*sin(2.55*2*pi*t); %eigenfrequenz vom Tesa-Spender

WriteGCode(amplitude,t,"test.gcode",1);

%%

% if max(abs(amplitude))>5
%     warning("amplitude >5, maximum amplitude is %3.2f",max(abs(amplitude)));
% else
%     fprintf("maximum amplitude is %3.2f\n",max(abs(amplitude)));
% end
% 
% %since we have negative locations/amplitudes no negative speed is necessary
% speed = abs(diff(amplitude))/dt;
% %we always start with 0 "displacement" therefore first speed value is also
% %0
% speed = [0 speed];
% speed_scale = 60; %weil mm/s, feed rate wird in mm/min angegeben
% speed = speed*speed_scale;
% 
% if max(abs(speed))>5000
%     warning("speed >5000, maximum speed is %3.2f",max(abs(speed)));
% else
%     fprintf("maximum speed is %3.2f\n",max(abs(speed)));
% end
% 
% figure;
% subplot(2,1,1);
% plot(t,amplitude);
% xlabel("time [s]");ylabel("amplitude [mm]");
% subplot(2,1,2);
% plot(t,speed);
% xlabel("time [s]");ylabel("schbeed [mm/s]");
% 
% % s.flush
% line = [];
% % s.writeline("G90");
% 
% fileID = fopen("test.gcode","W");
% % fprintf(fileID,"G21G90\n");
% 
% fprintf(fileID,"G01G21G90X0F100\n");
% fprintf(fileID,"G4P2\n");
% 
% for i=2:length(t)
%     cmd{i} = sprintf(formatSpec,amplitude(i),speed(i));
%     fprintf(fileID,cmd{i});
%     fprintf(fileID,"\n");
%     
% %     line = s.readline();
% %     str1 = strfind(line, "Error");
% %     str2 = strfind(line, "error");
% %     if str2>0
% %         warning("error");
% %     end
%     
% end
% 
% % fprintf(fileID,"G21G90X0F100\n");
% 
% fclose(fileID);