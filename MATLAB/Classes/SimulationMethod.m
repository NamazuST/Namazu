classdef (Abstract) SimulationMethod
    %SIMULATIONMETHOD Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        name string
        signal (:,2) double
        filename string
        setup = false
        nStepsPerSecond = 100
        T_max = 10
    end

    methods

        function obj = SimulationMethod(nStepsPerSecond,T_max)
            obj.nStepsPerSecond = nStepsPerSecond;
            obj.T_max = T_max;
            obj.filename = "";
        end

        function [pos,t] = getSignal(obj)
            t = obj.signal(:,1);
            pos = obj.signal(:,2);
        end

        function [fig] = plotSignal(obj)
            fig = figure;
            plot(obj.signal(:,1),obj.signal(:,2));
        end
    end
    
    methods(Abstract)
        obj = Setup(obj)
    end
end

