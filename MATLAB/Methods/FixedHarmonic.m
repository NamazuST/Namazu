classdef FixedHarmonic < SimulationMethod
    %FIXEDHARMONIC Simulation of a simple harmonic signal with fixed
    %parameters
    %   Class takes in frequencies, amplitudes and phases and simulates a
    %   signal based on the summation of the components. 
    
    properties
        frequencies (1,:) double
        amplitudes (1,:) double
        phases (1,:) double
    end
    
    methods
        function obj = FixedHarmonic(nStepsPerSecond,T_max)
            obj@SimulationMethod(nStepsPerSecond,T_max); % call base constructor
            obj.name = "FixedHarmonic";
        end
        
        function obj = Setup(obj)
            
            if ~obj.setup || ~strcmp(input("Load previous data? y/n\n",'s'),'y')
                
                inp = input( ['Enter Frequencies (' mat2str(obj.frequencies) ')\n'], "s");
                if ~isempty(inp)
                    freq_ = eval(['[' inp '];']);
                else
                    freq_ = obj.frequencies;
                end
                inp = input( ['Enter Amplitudes (' mat2str(obj.amplitudes) ')\n'], "s");
                if ~isempty(inp)
                    amp_ = eval(['[' inp '];']);
                else
                    amp_ = obj.amplitudes;
                end
                inp = input( ['Enter Phases (' mat2str(obj.phases) ')\n'], "s");
                if ~isempty(inp)
                    phase_ = eval(['[' inp '];']);
                else
                    phase_ = obj.phases;
                end
                
                if ~isempty(freq_)
                    obj.frequencies = freq_;
                end

                if all(size(amp_) == size(obj.frequencies))
                    if ~isempty(amp_)
                        obj.amplitudes = amp_;
                    end
                else
                    error("Dim mismatch in amplitudes!")
                end
                if all(size(phase_) == size(obj.frequencies))
                    if ~isempty(phase_)
                        obj.phases = phase_;
                    end
                else
                    error("Dim mismatch in phases!");
                end
            end

            [pos,t,name] = obj.SimulateFixedHarmonic();

            obj.signal = [t',pos'];
            obj.filename = name;

            obj.setup = true;
        end

        function [pos,t,name] = SimulateFixedHarmonic(obj)
        %SIMULATEFIXEDHARMONICS Simulate Fixed Harmonic Signal
        %   Generates oscillatory signals of 1-N frequencies with different
        %   amplitude values for a specific time duration.
        %INPUT:
        %   omega:  scalar value of a frequency or an array of several overlapping
        %   frequencies in HZ
        %   amp:    Amplitude factor in mm for the respective frequency, scalar or array
        %   maxT:   scalar value of the maximum simulation time in seconds
        %   varargin: can contain a manually chosen 'nStepsPerSecond' 
        %   number of timeStepsPerSecond
        %   the default value is 100.
        %
        % OUTPUT:
        %   pos: signal position in mm
        %   t: Specific time discretisation suited to the signal
        %   name: File name

            nFreq = length(obj.frequencies);
            %"time" space
            t = linspace(0,obj.T_max,obj.nStepsPerSecond*obj.T_max);
        
            pos = zeros(1,length(t));
            
            for i=1:nFreq
                pos = pos + obj.amplitudes(i)*sin(obj.frequencies(i)*2*pi*t + obj.phases(i));
            end
        
            freqName = 'om_';
            ampName = 'amp_';
            phaseName = 'phase_';
        
            for i=1:nFreq
                freqName = [freqName num2str(obj.frequencies(i)) '_'];
                ampName = [ampName num2str(obj.amplitudes(i)) '_'];
                phaseName = [phaseName num2str(obj.phases(i)) '_'];
            end
            name = [freqName ampName phaseName num2str(obj.T_max) '_' num2str(obj.nStepsPerSecond)];

        end
    end
end

