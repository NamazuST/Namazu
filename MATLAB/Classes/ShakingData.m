classdef ShakingData
    %SHAKINGDATA Class to hold and manage data simulated for and measured
    %by the shaking table
    %   Coded by Marius Bittner, MSc, and Jan Grashorn, MSc, on the
    %   28.02.2023
    
    properties
        dataPlate timetable; % data measured from the table itself
        dataObject timetable; % data measured from the object
        transformedDataPlate double;
        transformedDataObject double;
    
        anglesSensorPlate (3,1) double;
        anglesSensorObject (3,1) double;
    
        accelerationSensorsActive logical; % Acceleration sensors active or not
        numberOfAccSensors double = 5;     % How many sensors are attached
    
        accelerationSensorPort string = "COM9";
        accelerationSensorBaud double = 115200;
        accelerationSensorSampleRate double = 100;
    
        sensorRigData table;
        sensorRigValidationMeans table;

        estimatedFrequencies (1,:) double;
    
        motorStartupDelay double;
        motionStartupDelay double;
    
        sampleRate double;
        motorRate double;
    
        inputSignal (:,2) double;
        inputVelocity (:,2) double;
        inputAcceleration (:,2) double;
    
        marvCode string;
        signalFiltered logical;
        simulationType
        fileName string;
        signalGenerator MethodEnum;
        psdFunc function_handle;
    end
    
    methods
        function obj = ShakingData()
            obj.signalFiltered = false;
        end
        
        %Numerical differentiation to obtain speed and velocity values from
        %the position signal
        function obj = Setup(obj)
            %adds a 0 as initial value for the first time step
            obj.inputVelocity = [obj.inputSignal(:,1),...
                [0;diff(obj.inputSignal(:,2)) ./ diff(obj.inputSignal(:,1))]];
            obj.inputAcceleration = [obj.inputSignal(:,1),...
                [0;diff(obj.inputVelocity(:,2)) ./ diff(obj.inputSignal(:,1))]];
        end
        
        %Function to retrieve the parameters of the custom SRM PSD
        %function
        function params = GetPSDfuncParams(obj)
            temp_func_handle = functions(obj.psdFunc);
            params = temp_func_handle.workspace{1};
        end
    end
end

