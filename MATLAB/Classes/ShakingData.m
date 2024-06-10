classdef ShakingData
    %SHAKINGDATA Class to hold and manage data simulated for and measured
    %by the shaking table
    %   Coded by Marius Bittner, MSc, and Jan Grashorn, MSc, on the
    %   28.02.2023
    
    properties
        dataPlate timetable; % data measured from the table itself
        dataObject timetable; % data measured from the object (so far only one object is supported)
        transformedDataPlate double;
        transformedDataObject double;
        anglesSensorPlate (3,1) double;
        anglesSensorObject (3,1) double;
        accelerationSensorsActive logical; % Acceleration sensors active or not
        numberOfAccSensors double; %How many sensors are attached
        motorStartupDelay double; %Delay in s after which the motor starts, when sensors are already running
        motionStartupDelay double; %Time passes MATLAB and the user need to startup the motor after sensor setup
        sampleRate double; % sampling rate of the measurements
        motorRate double; % rate of the motor
        inputSignal (:,2) double; % vector [time,amplitude] for the simulated signal
        inputVelocity (:,2) double; % vector [time,amplitude] for simulated velocity (interpolated from position)
        inputAcceleration (:,2) double, % vector [time,amplitude] for simulated acceleration (interpolated from position)
        marvCode string; % generated marv-code
        signalFiltered logical; % Is the signal filtered or zero padded
        simulationType % TODO: Find out how to do enumerates so we can use one here to indicate the used method (Shinozuka, fixed Harmonic etc.)
        fileName string; % file name and location to save the accumulated data
        signalGenerator MethodEnum; %Which method to generate a pos signal was used?
        psdFunc function_handle; %If Shinozuka(SRM) was used with a custom PSD, this is the place to find it later.
        % to later access information of the stored parameters use currentSimulationData.GetPSDfuncParams, it is based on ff = functions(PSD); ff.workspace{1}; (possible in MATLAB2023a)
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

