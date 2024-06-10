clc; clear;
%Starting
fprintf('[%s]: ', datetime("now"))
fprintf('Starting %s. \n ',mfilename)

%% Path Dependencies
% Root Path
delimiter = filesep;
rootpath    = [pwd filesep];
addpath(genpath([rootpath 'Methods' filesep])); % Signal generating methods
addpath(genpath([rootpath 'Functions' filesep])); % MATLAB functions
addpath(genpath([rootpath 'Classes' filesep])); % MATLAB classes

%Set default plot text interpreter to latex
set(0,'defaulttextinterpreter','latex')
set(0,'defaultAxesFontSize',12)

%% Initialization of the setup
currentSimulationData = ShakingData();

t = []; % time vector
pos = []; % position vector

%Are the acceleration sensors operating?
currentSimulationData.accelerationSensorsActive = false;

%% Choice of method

% Numbering and identification List
% settings.method.shinozuka = 0;
% settings.method.ShinozukaBenchmark = 1;
% settings.method.FixedHarmonic = 2;
% settings.method.RandomHarmonic = 3;
% settings.method.EarthquakeRecord = 4;

usedMethod = MethodEnum.FixedHarmonic;

%These options are fixed for some cases, e.g. ShinozukaBenchmark
stepsPerSecond = 100;
maxT = 10;
filterLength = 3;

switch usedMethod
    case MethodEnum.Shinozuka
        usedPSD = 'KT';
        if isequal(usedPSD, 'LOL')
            maxF = 12; % [Hz]
            nOmega = 50;
            ampPSD = 0.01;
            PSD = @(omega) ampPSD*(abs(omega)<maxF*2*pi);
            name = usedPSD;
            currentSimulationData.psdFunc = PSD;
        elseif isequal(usedPSD, 'KT')
            %Kanai-Tajimi PSD function
            maxF = 15; %mx frequency of the signal
            nOmega = 150; %number of omega discretizations
            %scale function parameters
            w_g = 9*2*pi; %peak frequency
            beta_g = 0.6;
            %scale whole PSD function amplitude
            S_0 = 0.01;
            PSD = @(omega) ( w_g^4 + (2*beta_g*w_g*omega).^2 ) ./ ((w_g^2-omega.^2).^2 + (2*beta_g*w_g*omega).^2 ) .* S_0;
            name = usedPSD;
            % to later access information of the stored parameters use currentSimulationData.GetPSDfuncParams
            currentSimulationData.psdFunc = PSD;
        end
        %SimulateShinozuka, inpt: PSD [f(\omega)], maxT [s], maxOmega
        %[rad/s], nOmega [-]

        [pos,t,~] = SimulateShinozuka(PSD,maxT,maxF*2*pi,nOmega,'nStepsPerSecond',stepsPerSecond);
        %optional autocorr function to check correlation of the signal,
        %required econometrics toolbox, alternatively get: https://de.mathworks.com/matlabcentral/fileexchange/30540-autocorrelation-function-acf
        % figure
        % autocorr(pos,'NumLags',length(t)-1)

        % shift to start with 0 pos
        pos = pos-pos(1);
        currentSimulationData.inputSignal = [t',pos'];
        currentSimulationData.motorRate = stepsPerSecond;
        methodName = 'Shinozuka';
    case MethodEnum.ShinozukaBenchmark
        %Scaling factor, if no scaling is desired do not hand this to the
        %function
        Shinozuka_amplitude_scaling = 3;
        [pos,t,dt,maxT,name] = SimulateShinozukaBenchmark(Shinozuka_amplitude_scaling);
        currentSimulationData.inputSignal = [t',pos'];
        currentSimulationData.motorRate = (length(t)-1)/t(end);
        methodName = 'ShinozukaBenchmark';
    case MethodEnum.FixedHarmonic
        %simulateFixedHarmonic, inpt: omega [Hz], amp [mm], maxT [s]
        % fixed harmonic
        %         [pos,t,name] = SimulateFixedHarmonic(4,1,maxT,'nStepsPerSecond',stepsPerSecond);
        
        % Fibonacci
        %        [pos,t,name] = SimulateFixedHarmonic([1.6,4.1,6.6],[1,2,1],maxT,'nStepsPerSecond',stepsPerSecond);

        [pos,t,name] = SimulateFixedHarmonic(1,1,maxT,'nStepsPerSecond',stepsPerSecond);
        currentSimulationData.inputSignal = [t',pos'];
        currentSimulationData.motorRate = stepsPerSecond;
        methodName = 'HarmonicSignal';
    case MethodEnum.RandomHarmonic
        %simulateRandomHarmonic, input: omegaBase, ampBase, nOmega, maxT
        [pos,t,name] = SimulateRandomHarmonic(1,0.1,5,maxT,'nStepsPerSecond',stepsPerSecond);
        currentSimulationData.inputSignal = [t',pos'];
        currentSimulationData.motorRate = stepsPerSecond;
        methodName = 'RandomHarmonic';
    case MethodEnum.EarthquakeRecord
        [pos,t,name] = SimulateEarthquake();
        stepsPerSecond = 1/t(2);
        maxT = t(end);
        currentSimulationData.inputSignal = [t,pos];
        currentSimulationData.motorRate = stepsPerSecond;
        currentSimulationData.signalGenerator = usedMethod;
        methodName = 'Earthquake';
    case MethodEnum.ImportSignal
        %name of the file to load
        fname = 'arbitrarilychosensignal.mat';
        load(fname)
        name = fname(1:end-4);
        %Extract steps per second
        stepsPerSecond = 1/t(2);
        maxT = t(end);
        %disable the filter length because an imported signal could already
        %be filtered
        filterLength = 0;
        % dimensions for input must be
        % t: [1xn_time_vector]
        % and pos: [1xn_pos_vector]
        currentSimulationData.inputSignal = [t', chosen_signal];
        currentSimulationData.motorRate = stepsPerSecond;
        currentSimulationData.signalGenerator = usedMethod;
        methodName = 'ImportSignal';
    otherwise
        error('Method not implemented!');
end

fprintf(['Starting experiment for a ', methodName, '.\n'])

%% Marvcode generation

%String for filename including timecode
fName = [rootpath 'MarvCode' delimiter ...
    char(datetime('now','Format','yMMd_HHmmss_SSS')) '_' ...
    methodName, '_', name, '.mat'];

% Set the used method to generate the input signal
currentSimulationData.simulationType = usedMethod;

% Set the name for this particular experiment
currentSimulationData.fileName = fName;

% Filtering the Motor Input is optional? -> Depends on the signal

%the 1 stands for 1 second of acceleration to the real position and 1
%second of deacceleration till the end of the real signal
%this is for smoother steering of the motor
currentSimulationData = FilterMotorInput(currentSimulationData,filterLength);

%Setup for now computes numerically speed and acceleration of the input
%signal
currentSimulationData = currentSimulationData.Setup();

%% Intermediate Control plots

figure;
subplot(3,1,1)
plot(currentSimulationData.inputSignal(:,1),currentSimulationData.inputSignal(:,2)); title("Position $[mm]$");
subplot(3,1,2);
plot(currentSimulationData.inputSignal(:,1),currentSimulationData.inputVelocity(:,2)); title("Velocity $[mm/s]$");
subplot(3,1,3);
plot(currentSimulationData.inputSignal(:,1),currentSimulationData.inputAcceleration(:,2)./1000); title("Acceleration $[m/s^2]$");

fprintf("Max Amplitude: %3.2f [mm], max velocity: %3.2f [mm/s], max acceleration: %3.2f [m/s^2]\n",...
    max(abs(currentSimulationData.inputSignal(:,2))),max(abs(currentSimulationData.inputVelocity(:,2))),...
    max(abs(currentSimulationData.inputAcceleration(:,2)./1000)));

%% find shaking table controller on the correct COM port, COM port needs to be identified manually

dev = serialport("COM3",921600);
pause(0.1)
dev.flush
fprintf(['Number of Bytes available: ', num2str(dev.NumBytesAvailable), '.\n'])

%% write data to stepper

if ~strcmp(input("Continue with writing data to stepper? y/n\n",'s'),'y')
    error("Aborted");
end

currentSimulationData = WriteMarvCode(currentSimulationData);
SendDataToMotor(currentSimulationData,dev);

%% Shaking

if ~strcmp(input("Continue with starting the experiment? y/n\n",'s'),'y')
    error("Aborted");
end

% error("NOT IMPLEMENTED");

% Main function to start the experiment
currentSimulationData = StartExperiment(currentSimulationData,dev);

save(currentSimulationData.fileName,'currentSimulationData');

%% Post-processing
%currently only supported for acceleration sensors

if currentSimulationData.accelerationSensorsActive
    %Set the lowpass frequency above which all frequencies are filtered out
    lowpassFrequency = 20;
    AnalyzeData(currentSimulationData, lowpassFrequency);
end

%Le Finy
fprintf('[%s]: ', datetime("now"))
fprintf('Finished %s.\n',mfilename)