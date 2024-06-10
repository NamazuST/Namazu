function [currentSimulationData] = StartExperiment(currentSimulationData,dev)

%Are sensores connected or not?
if currentSimulationData.accelerationSensorsActive == true

    %Check for Sensor Arduino port
    portList = serialportlist("available");
    port = 'COM4';

    if exist("a",'var')
        if class(a)=="arduino"
            disp("Arduino found on port!");
        end
    elseif sum(port==portList)==0
        error('Port not found/open or port is in use, check USB connection!')
    else
        a = arduino(port,'Nano3','Libraries','I2C');
    end

    sampleRate = 100;
    dt = 1/sampleRate;
    samplesPerRead = sampleRate;

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

%     p2 = subplot(2,1,2);
%     xlabel('t [s]');
%     ylabel('Acceleration $(m/s^2)$');
%     title('Acceleration values from mpu6050 sensor 2');
%     x2_val = animatedline('Color',[0 0.4470 0.7410]);
%     y2_val = animatedline('Color',[0.8500 0.3250 0.0980]);
%     z2_val = animatedline('Color',[0.9290 0.6940 0.1250]);
%     axis tight;
%     legend('X','Y','Z');
    
    count = 0;
    data1 = [];
%     data2 = [];

    imu = mpu6050(a,'I2CAddress','0x68','SampleRate',sampleRate,...
        'SamplesPerRead',samplesPerRead,'OutputFormat','timetable','ReadMode','latest');
%     imu2 = mpu6050(a,'I2CAddress','0x69','SampleRate',sampleRate,...
%         'SamplesPerRead',samplesPerRead,'OutputFormat','timetable','ReadMode','latest');
    fprintf('Sensors initialized. \n')

    pause(1);
    
    %Indicator for the motor startup to set a delay for the acc sensors
    started = 0;
    %Acc sensor delay
    currentSimulationData.motorStartupDelay = 0;
    

    if ~strcmp(input("Start the motion? y/n\n",'s'),'y')
        error("Aborted");
    end
    tic;
    %Sensors acquire 5s longer signal
    while(toc <= currentSimulationData.inputSignal(end,1)+5)

        [accel1] = imu.read;
%         [accel2] = imu2.read;
        data1 = [data1;accel1];
%         data2 = [data2;accel2];
        
        %if check for a first setup loop to start the reading, then check
        %if the motorStartupDelay in seconds is reached
        if ~started && toc > currentSimulationData.motorStartupDelay
            %some kind of time before starting to read the sensors
            SensorStart = tic;
            %time after the button has been pressed and sensors are up
            motionStart = toc(SensorStart);
            currentSimulationData.motionStartupDelay = motionStart;
            SendInstructionToUSB(dev,'start',1);
            started = 1;
        end

        X = (count+1:count+size(accel1,1))*dt;
        addpoints(x1_val,X,accel1.Acceleration(:,1));
        addpoints(y1_val,X,accel1.Acceleration(:,2));
        addpoints(z1_val,X,accel1.Acceleration(:,3));

%         addpoints(x2_val,X,accel2.Acceleration(:,1));
%         addpoints(y2_val,X,accel2.Acceleration(:,2));
%         addpoints(z2_val,X,accel2.Acceleration(:,3));

        p1.XLim = [max(0,X(end)-10) X(end)];
%         p2.XLim = [max(0,X(end)-10) X(end)];

        count = count + size(accel1,1);
        %drawnow limitrate;
        drawnow

    end
    imu.flush;
%     imu2.flush;
    toc
    eltime = toc;
    
    currentSimulationData.dataPlate = data1;
%     currentSimulationData.dataObject = data2;
    currentSimulationData.sampleRate = sampleRate;

else
    tic

    SendInstructionToUSB(dev,'start');

    %Since no sensors where applied, not data existent
    currentSimulationData.dataPlate = timetable;
    currentSimulationData.dataObject = timetable;
    currentSimulationData.sampleRate = 0;
    
    toc

end


