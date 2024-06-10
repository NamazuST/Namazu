function [pos,t,name] = SimulateEarthquake()
%SIMULATEEARTHQUAKE To apply a in amplitude scaled signal
%   This function should apply an earthquake signal to the table motion,
%   the position is roughly approximated from an rathquake's accelerogram
%   However this function does only scale the amplitude and doesn't concern
%   the energy content.

name = 'EQ_ElCentro';
%threshold set for maximum displacement achieved with ElCentro
threshold_displacements = 30;
%File seperator for the current system
fsep = filesep;
%Location of El Centro EQ signal
eq_record_el_Centro = fullfile([pwd, fsep, 'Methods', fsep, 'earthquake_records'], 'elcentrons.txt');
%Load the El Centro time and accelerogram into an array
M_elcentro = readmatrix(eq_record_el_Centro);

%loaded time in seconds
t = M_elcentro(:,1);

%loaded acceleration in g
acc = M_elcentro(:,2);
%converting acceleration from g in mm/s^2
acc = acc*9810;
%speed in mm/s
speed = cumtrapz(t, acc);
%position in mm
pos = cumtrapz(t, speed);
a0 = t\pos;
pos = pos-a0*t;
%scale maximum displacement to be 10mm
pos = (pos./max(pos)).*threshold_displacements;

end

