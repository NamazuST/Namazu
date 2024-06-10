function [shakingData] = FilterMotorInput(shakingData,tUp,tDown)
%FilterMotorInput
%the tUp, tDown stands for a time in second of acceleration to the real
%position (tUp) and a time in second of deacceleration (tDown) till the end of the real signal
%this is for smoother steering of the motor
%INPUT:
%   shakingData: Current shakingData object, containing input signal and
%   time domain
%   tUp: starting duration till when a linear ramp up of the position is taking place
%   tDown: ending duration (T-tDown) how long a deceleration of the signal
%   is applied
% OUTPUT:
%   pos: Gaussian process with specific features according to Shinozuka and
%   Deodatis
%   time: Specific time discretisation suited to the process
%   name: File name

%acceleration and deacceleration time is the same
if ~exist("tDown",'var')
    tDown = tUp;
end

%Identify used method
usedMethod = shakingData.simulationType;

%For now only an exception is made regarding the Shinozuka benchmark
%example
switch usedMethod
    
    %Linear ramp up and down is neglected for Shinozuka Benchmark but a 0
    %is added for the initial time step, this needs to be disregarded for
    %the post-processing
    case MethodEnum.ShinozukaBenchmark
        
        %loading of position and time data
        pos = shakingData.inputSignal(:,2);
        t = shakingData.inputSignal(:,1);
        
        %Zero padding of the position input signal
        %for safety reasons we need the position at time 0 to be 0, no
        %matter what.
        pos = [0; pos];
        t = [t; t(end)+t(2)];
        
        %Delete previously stored input signal
        shakingData.inputSignal = [];

        %Save extended time and zero padded position signal
        shakingData.inputSignal = [t, pos];
        
        %shakingData input signal is filtered
        shakingData.signalFiltered = true;
        
    otherwise
        
        %loading of position and time data
        pos = shakingData.inputSignal(:,2);
        t = shakingData.inputSignal(:,1);
        
        %deacceleration time
        absTDown = t(end)-tDown;
        
        %acceleration and deacceleration time is dependant on signal generator method, because
        %EQ records do not necessarily stop at 0 mm
        if isequal(shakingData.signalGenerator,MethodEnum.EarthquakeRecord)
            
            %Drive back very slowly to position 0, after the signal
            steps2return = 300;
            pos = [pos; linspace(pos(end), pos(1), steps2return)'];
            t = [t; linspace(t(end), t(end)+t(2)*steps2return, steps2return)'];
            
            %Delete previously stored input signal
            shakingData.inputSignal = [];
            
            %Safe the time including the returing path
            shakingData.inputSignal = [t, pos];
            
            %shakingData input signal is filtered
            shakingData.signalFiltered = true;
            
        else
            
            %acceleration time
            pos(t<tUp) = t(t<tUp)./tUp.*pos(t<tUp); % linear ramp up
            %deacceleration time
            pos(t>absTDown) = pos(t>absTDown) .* (1-(t(t>absTDown)-absTDown)./(t(end)-absTDown)); %"linear ramp down"
            %Safe the deaccelerated position signal
            shakingData.inputSignal(:,2) = pos;
            %shakingData input signal is filtered
            shakingData.signalFiltered = true;
            
        end
        
end

end

