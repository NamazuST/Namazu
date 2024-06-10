%% Establish connection

%Check for Sensor Arduino port
portList = serialportlist("available");

%For an automatic search, a pre identification of what kind of device
%is connected to the com port is needed, if I directly use arduino on a
%port where no arduino is connected, it ends up in a inifite loop.

% for j=1:length(portList)
%     search_port = portList(j);
%     try
%         a = arduino(search_port,'Nano3','Libraries','I2C');
%     catch
%     end
% end

%Manual selection of the correct port of the arduino board
port = 'COM4';

if exist("a",'var')
    if class(sensor_arduino)=="arduino"
        disp("Arduino found on port!");
    end
elseif sum(port==portList)==0
    error('Port not found/open or port is in use, check USB connection!')
else
    sensor_arduino = arduino(port,'Nano3','Libraries','I2C');
    disp("Arduino seems to be identified and connected.");
end

%% Generate accelerometer instances and objects

sampleRate = 100;
dt = 1/sampleRate;
samplesPerRead = sampleRate;

count = 0;

imu = mpu6050(sensor_arduino,'I2CAddress','0x69','SampleRate',sampleRate,...
    'SamplesPerRead',samplesPerRead,'OutputFormat','timetable','ReadMode','latest');
% imu2 = mpu6050(a,'I2CAddress','0x69','SampleRate',sampleRate,...
%     'SamplesPerRead',samplesPerRead,'OutputFormat','timetable','ReadMode','latest');

%Read for 10 seconds
stop_time = 120;
time_vec = linspace(0,10,100);

%% Figureine
figure;
p1 = subplot(2,1,1);
xlabel('t [s]');
ylabel('Acceleration $(m/s^2)$');
title('Acceleration values from mpu6050 sensor 1');
x1_val = animatedline('Color',[0 0.4470 0.7410]);
y1_val = animatedline('Color',[0.8500 0.3250 0.0980]);
z1_val = animatedline('Color',[0.9290 0.6940 0.1250]);
axis tight;
legend('X','Y','Z');

% p2 = subplot(2,1,2);
% xlabel('t [s]');
% ylabel('Acceleration $(m/s^2)$');
% title('Acceleration values from mpu6050 sensor 2');
% x2_val = animatedline('Color',[0 0.4470 0.7410]);
% y2_val = animatedline('Color',[0.8500 0.3250 0.0980]);
% z2_val = animatedline('Color',[0.9290 0.6940 0.1250]);
% axis tight;
% legend('X','Y','Z');

%Start timestap
tic;
%Start reading
while(toc < stop_time)
    [accel1] = imu.read;
    %[accel2] = imu2.read;
    X = (count+1:count+size(accel1,1))*dt;
    addpoints(x1_val,X,accel1.Acceleration(:,1));
    addpoints(y1_val,X,accel1.Acceleration(:,2));
    addpoints(z1_val,X,accel1.Acceleration(:,3));

%     addpoints(x2_val,X,accel2.Acceleration(:,1));
%     addpoints(y2_val,X,accel2.Acceleration(:,2));
%     addpoints(z2_val,X,accel2.Acceleration(:,3));

    p1.XLim = [max(0,X(end)-10) X(end)];
%     p2.XLim = [max(0,X(end)-10) X(end)];

    count = count + size(accel1,1);
    %drawnow limitrate;
    drawnow
    disp(datetime("now"))
end
imu.flush;
%imu2.flush;
toc;

% adjusted time (possbily wrong)
% figure
% plot(time_vec,accel1.Acceleration)
% hold on
% plot(time_vec,accel2.Acceleration)
% 
% real time plot
% figure
% plot(accel1.Time,accel1.Acceleration)
% hold on
% plot(accel2.Time,accel2.Acceleration)