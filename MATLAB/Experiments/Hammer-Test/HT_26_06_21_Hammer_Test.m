%% Compatibility entry point for the current hammer-test campaign
%
% The former contents used the obsolete one-sensor, 500 Hz defaults. Keep
% this familiar filename as a safe redirect to the single source of campaign
% settings used by the five-sensor, 250 Hz ESP32 rig.

hammerTestFolder = fileparts(mfilename("fullpath"));
matlabRoot = fileparts(fileparts(hammerTestFolder));
campaignScript = fullfile( ...
    matlabRoot, ...
    "Functions", ...
    "FunTests", ...
    "Script_Prepare_HT_26_06_21_Hammer_Test.m");

run(campaignScript);
