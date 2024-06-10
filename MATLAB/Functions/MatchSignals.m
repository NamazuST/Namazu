function [s1,s2] = MatchSignals(s1,s2,F1,F2)
%%MATCHSIGNALS(s1,s2): Matches signal s2 to signal s1

    % Resamples s2 to the sampling rate of s1, then uses
    % alignsignals-function to match both signals
    % INPUTS:
    % s1, s2: vector of measured data
    % F1, F2: sampling rate in Hz
    % Note: For DIC this is the FPS settings of the recordings, for
    % accelerometers it is the sampling rate, for input signals it is the
    % discretization of the input (1/dT)

    [P,Q] = rat((F1)/(F2));
    sOut = resample(s2,P,Q);

    [s1,s2] = alignsignals(s1,sOut);

end

