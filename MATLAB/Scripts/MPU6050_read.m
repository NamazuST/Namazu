clearvars -except dev;
% close all;

portList = serialportlist("available");
port = 'COM3';

if exist("a",'var')
    if class(a)=="arduino"
        disp("Arduino found on port!");
    end
elseif sum(port==portList)==0
    error('Port not found/open or port is in use, check USB connection!')
else
    a = arduino(port,'Nano3');
end

sampleRate = 100;
dt = 1/sampleRate;
samplesPerRead = sampleRate;

imu = mpu6050(a,'I2CAddress','0x68','SampleRate',sampleRate,'SamplesPerRead',samplesPerRead,'OutputFormat','timetable');
imu2 = mpu6050(a,'I2CAddress','0x69','SampleRate',sampleRate,'SamplesPerRead',samplesPerRead,'OutputFormat','timetable');

figure;
p1 = subplot(2,1,1);
xlabel('t [s]');
ylabel('Acceleration (m/s^2)');
title('Acceleration values from mpu6050 sensor 1');
x1_val = animatedline('Color',[0 0.4470 0.7410]);
y1_val = animatedline('Color',[0.8500 0.3250 0.0980]);
z1_val = animatedline('Color',[0.9290 0.6940 0.1250]);
axis tight;
legend('X','Y','Z');

p2 = subplot(2,1,2);
xlabel('t [s]');
ylabel('Acceleration (m/s^2)');
title('Acceleration values from mpu6050 sensor 2');
x2_val = animatedline('Color',[0 0.4470 0.7410]);
y2_val = animatedline('Color',[0.8500 0.3250 0.0980]);
z2_val = animatedline('Color',[0.9290 0.6940 0.1250]);
axis tight;
legend('X','Y','Z');

stop_time = 10;
count = 0;
data1 = [];
data2 = [];

% java -cp UniversalGcodeSender.jar com.willwinder.ugs.cli.TerminalClient --controller GRBL --port COM5 --baud 115200 --print-progressbar --file test.gcode
tic;
SendInstructionToUSB(dev,'start',1);
while(toc <= stop_time)

    [accel1] = imu.read;
    [accel2] = imu2.read;
    data1 = [data1;accel1];
    data2 = [data2;accel2];

    X = (count+1:count+size(accel1,1))*dt;
    addpoints(x1_val,X,accel1.Acceleration(:,1));
    addpoints(y1_val,X,accel1.Acceleration(:,2));
    addpoints(z1_val,X,accel1.Acceleration(:,3));

    addpoints(x2_val,X,accel2.Acceleration(:,1));
    addpoints(y2_val,X,accel2.Acceleration(:,2));
    addpoints(z2_val,X,accel2.Acceleration(:,3));

    p1.XLim = [max(0,X(end)-10) X(end)];
    p2.XLim = [max(0,X(end)-10) X(end)];

    count = count + size(accel1,1);
    drawnow limitrate;
%     drawnow

end
toc
eltime = toc;

data.data1 = data1;
data.data2 = data2;

SaveAccelerationData(
%% filtering
% load("D:\Wackeltisch\shaking-table\lastMeasurement.mat");
load("D:\Wackeltisch\shaking-table\lastSim.mat");
addpath("Functions\");

plotFiltered = 0;

t1 = zeros(length(data1.Time),1);
t2 = zeros(length(data2.Time),1);
t1(2:end) = cumsum(seconds(diff(data1.Time)));
t2(2:end) = cumsum(seconds(diff(data2.Time)));

alpha = 0.1;

a1 = data1.Acceleration(:,1);
a2 = data2.Acceleration(:,2);
a1Filtered = a1;
a2Filtered = a2;

for i=2:size(data1,1)
    a1Filtered(i,:) = a1Filtered(i-1,:)*alpha+(1-alpha)*(a1(i,:)-a1(i-1,:));
    a2Filtered(i,:) = a2Filtered(i-1,:)*alpha+(1-alpha)*(a2(i,:)-a2(i-1,:));
end

[amp1Filtered,f1Filtered] = fourier(a1Filtered,t1);
[amp2Filtered,f2Filtered] = fourier(a2Filtered,t2);

[amp1,f1] = fourier(a1,t1);
[amp2,f2] = fourier(a2,t2);

v1Filtered = zeros(length(a1Filtered),1);
v2Filtered = v1Filtered;
pos1Filtered = v1Filtered;
pos2Filtered = v1Filtered;

for i=2:length(v1Filtered)
    v1Filtered(i) = v1Filtered(i-1) + a1Filtered(i-1)*(t1(i)-t1(i-1));
    v2Filtered(i) = v2Filtered(i-1) + a2Filtered(i-1)*(t2(i)-t2(i-1));
    pos1Filtered(i) = pos1Filtered(i-1) + v1Filtered(i-1)*(t1(i)-t1(i-1));
    pos2Filtered(i) = pos2Filtered(i-1) + v2Filtered(i-1)*(t2(i)-t2(i-1));
end

if exist("t",'var')
    if exist("amplitude",'var')
        [ampSim,fSim] = fourier(amplitude,t);
    elseif exist("pos",'var')
        [ampSim,fSim] = fourier(pos,t);
    end
end

[ampPos1,fPos1] = fourier(pos1Filtered,t1);
[ampPos2,fPos2] = fourier(pos2Filtered,t2);

figure;
subplot(2,1,1);
if exist("fSim",'var') && exist("ampSim",'var')
     plot(f1,amp1./max(amp1),f2,amp2./max(amp2),fSim,ampSim./max(ampSim),'k--');
%     hold on; plot(f1Filtered,amp1Filtered./max(amp1Filtered),'b--',f2Filtered,amp2Filtered./max(amp2Filtered),'r--');
    legend({'Model','Plate','Sim','Model Filtered','Plate Filtered'})
else
    plot(f1,amp1./max(amp1),f2,amp2./max(amp2));legend({'Model','Plate'});
end
xlim([0,sampleRate/2]);
xlabel("Frequency [Hz]");ylabel("relative Amplitude");

subplot(2,1,2);
if exist("fSim",'var') && exist("ampSim",'var')
    plot(f1,amp1,f2,amp2,fSim,ampSim,'k--');
%     hold on; plot(f1Filtered,amp1Filtered./max(amp1Filtered),'b--',f2Filtered,amp2Filtered./max(amp2Filtered),'r--');
    legend({'Model','Plate','Sim','Model Filtered','Plate Filtered'})
else
    plot(f1,amp1,f2,amp2);legend({'Model','Plate'});
end
xlim([0,sampleRate/2]);
xlabel("Frequency [Hz]");ylabel("absolute Amplitude");
% figure;
% plot(t1,a1,t2,a2);legend({'out','Plate'});
% title("Unfiltered");
% figure;
% plot(t1,a1Filtered,t2,a2Filtered);legend({'out Filtered','Plate Filtered'});
% title("Filtered");
% figure;
% plot(fPos1,ampPos1./max(ampPos1),fPos2,ampPos2./max(ampPos2));legend({'Model','Plate'});
% title("Filtered position frequencies");
% figure;
% plot(t1,pos1Filtered,t2,pos2Filtered);
% title("Integrated position");