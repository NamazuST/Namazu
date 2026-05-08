function PlotCorrectedSensorRigData(currentSimulationData)
% PlotCorrectedSensorRigData
% Plots corrected acceleration data from the MPU6050 sensor rig.
%
% Usage:
%   PlotCorrectedSensorRigData(currentSimulationData)

%% -------------------- CHECK DATA --------------------
if ~isprop(currentSimulationData, "sensorRigData") || isempty(currentSimulationData.sensorRigData)
    error("currentSimulationData.sensorRigData is empty or does not exist.");
end

T = currentSimulationData.sensorRigData;
varNames = string(T.Properties.VariableNames);

%% -------------------- TIME AXIS --------------------
if ismember("t_arduino_elapsed_s", varNames)
    t = T.t_arduino_elapsed_s;
    timeLabel = "Arduino elapsed time [s]";
elseif ismember("t_matlab_elapsed_s", varNames)
    t = T.t_matlab_elapsed_s;
    timeLabel = "MATLAB elapsed time [s]";
elseif ismember("t_arduino_s", varNames)
    t = T.t_arduino_s - T.t_arduino_s(1);
    timeLabel = "Arduino time [s]";
else
    t = (0:height(T)-1).';
    timeLabel = "Sample index";
end

%% -------------------- NUMBER OF SENSORS --------------------
if isprop(currentSimulationData, "numberOfAccSensors") && ~isempty(currentSimulationData.numberOfAccSensors)
    NumSens = currentSimulationData.numberOfAccSensors;
else
    % Infer number of sensors from available corrected variable names
    sensorTokens = regexp(varNames, "^S(\d+)_ax_g_corr$", "tokens", "once");
    sensorIds = [];

    for i = 1:numel(sensorTokens)
        if ~isempty(sensorTokens{i})
            sensorIds(end+1) = str2double(sensorTokens{i}{1}); %#ok<AGROW>
        end
    end

    NumSens = max(sensorIds);
end

%% -------------------- PLOT SETTINGS --------------------
directions = ["x", "y", "z"];
axisNames = ["ax", "ay", "az"];

figure;
tiledlayout(3,1, "TileSpacing", "compact", "Padding", "compact");

for iDir = 1:3
    nexttile;
    hold on;
    grid on;
    box on;

    for iSens = 1:NumSens
        varName = sprintf("S%d_%s_g_corr", iSens, axisNames(iDir));

        if ismember(string(varName), varNames)
            plot(t, T.(char(varName)), ...
                "DisplayName", sprintf("Sensor %d", iSens));
        else
            warning("Variable %s not found. Skipping sensor %d.", varName, iSens);
        end
    end

    xlabel(timeLabel, "Interpreter", "none");    
    ylabel(sprintf("$a_%s$ corrected [g]", char(directions(iDir))), ...
           "Interpreter", "latex");    
    title(sprintf("Corrected acceleration in %s-direction", directions(iDir)), ...
          "Interpreter", "none");
end

end