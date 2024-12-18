classdef ShakingData
    %SHAKINGDATA Class to hold and manage data simulated for and measured
    %by the shaking table
    %   Coded by Marius Bittner, MSc, and Jan Grashorn, MSc, on the
    %   28.02.2023
    
    properties
        motorStartupDelay double; %Delay in s after which the motor starts, when sensors are already running
        motionStartupDelay double; %Time passes MATLAB and the user need to startup the motor after sensor setup
        sampleRate double; % sampling rate of the measurements
        stepsPerMM double; % how many steps the motor has to turn for a millimeter of displacement
        inputSignal (:,2) double; % vector [time,amplitude] for the simulated signal
        inputVelocity (:,2) double; % vector [time,amplitude] for simulated velocity (interpolated from position)
        inputAcceleration (:,2) double, % vector [time,amplitude] for simulated acceleration (interpolated from position)
        marvCode string; % generated marv-code
        signalFiltered logical; % Is the signal filtered or zero padded
        fileName string; % file name and location to save the accumulated data
        simulationMethod (1,1) SimulationMethod = FixedHarmonic(100,10); %Which method to generate a pos signal was used?
        % to later access information of the stored parameters use currentSimulationData.GetPSDfuncParams, it is based on ff = functions(PSD); ff.workspace{1}; (possible in MATLAB2023a)
    end

    methods
        function obj = ShakingData(simMethod,stepsPerMM)
            obj.simulationMethod = simMethod;
            obj.sampleRate = obj.simulationMethod.nStepsPerSecond;
            obj.stepsPerMM = stepsPerMM;
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

