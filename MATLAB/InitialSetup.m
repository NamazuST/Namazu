function [rootpath] = InitialSetup()
    %Starting
    fprintf('[%s]: ', datetime("now"))
    fprintf('Starting %s. \n ',mfilename)
    
    %% Path Dependencies
    % Root Path
    rootpath    = [pwd filesep];
    addpath(genpath([rootpath 'Methods' filesep])); % Signal generating methods
    addpath(genpath([rootpath 'Functions' filesep])); % MATLAB functions
    addpath(genpath([rootpath 'Classes' filesep])); % MATLAB classes
    
    %Set default plot text interpreter to latex
    % set(0,'defaulttextinterpreter','latex')
    % set(0,'defaultAxesFontSize',12)
    
end

