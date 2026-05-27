function [pos,t,name,accMissmatch] = SimulateEarthquake(~)
%SIMULATEEARTHQUAKE To apply a in amplitude scaled signal
% the scaling method has to be changed accordingly (Cauchy/Froude), this might change the outcome significantly 

name = 'EQ_ElCentro';
                                                                        
%File seperator for the current system
fsep = filesep;
%Location of El Centro EQ signal
eq_record_el_Centro = fullfile([pwd, fsep, 'Methods', fsep, 'earthquake_records'], 'elcentrons.txt');

%Load the El Centro time and accelerogram into an array
M_elcentro = readmatrix(eq_record_el_Centro); 

%loaded acceleration in g
accOrigin = M_elcentro(:,2); 

%converting acceleration from g in mm/s^2 
acc = accOrigin.*(9810);

%loaded time in seconds
t = M_elcentro(:,1); 

%% Scaling
scalingMethod = 'Cauchy'; % could also be defined in MainCreateSimulation

%input length scale 
lengthScale = 0.53; 

%input Youngs modulus ratio of specimen to prototype 
EScale = 1; 

%input material density ratio of specimen to prototype 
rhoScale = 1; 

%place holder for Cauchy scaling
accMissmatch = 9.81; 


switch scalingMethod
    case 'Froude'                    

        % Time scaling only 
        t= t .* sqrt(lengthScale);
        % Acceleration is *not* scaled 
        
    case 'Cauchy'                  
        % Time scaling
        t = t .* ( lengthScale * (1/sqrt(rhoScale)) * sqrt(EScale) );
        % Acceleration scaling 
        acc = acc .* ( EScale * (1/rhoScale) * lengthScale ); 
        % Acceleration miss match (g distortion) 
        accMissmatch = 9.81/( EScale * (1./rhoScale) * lengthScale); 
        
         if t == sqrt(lengthScale) 
           disp('Froude-Cauchy condition true')
         end 
    otherwise
        error('Unsupported scaling method. Use ''Froude'' or ''Cauchy''.');
end

%% integration 
% cumaltive trapizoids
%speed in mm/s and detrend 
speed_int = cumtrapz(t, acc);
speed = detrend(speed_int,1);

%position in mm and detrend 
pos_int= cumtrapz(t, speed);
pos = detrend(pos_int,1); 

% filter starting displacement 0 Linear interpol
pos(1:5) = 0; 
for i = 6:15
    % Linear interpolation between zero and the actual value
    interp_factor = (i - 5) / (15 - 5);
    pos(i) = pos(i) * interp_factor/5;  % abitrary devison for softer entry 
end

                                                                             
% OLD SAFTY CAP WAS 30mm CHECK CURRENT SHAKING TABLE
%% safety restricted displacement - search for max. displacement in current Namazu framework
 if max(abs(pos)) > 50
     pos = NaN; 
     disp('Scaling to big, maximal displacement should be under 50 [mm]')
 end 

%% Plot for reference 
% plot(t,pos); 
% box off
% xlabel('t in $$ [s] $$')
% ylabel('displacement $$ [mm] $$')
% fname = 'Displacement input namazu';

%% Output acceleration missmatch
disp(['Required gravitational acceleration: ',num2str(accMissmatch),' in [g]' ...
    ' the acceleration distorted by factor ',num2str(accMissmatch/9.81),]); 
end 
