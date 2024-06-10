function [shakingData] = TransformCoordinateSystemOfMeasurement(shakingData)

    % !!!! WORK IN PROGRESS !!!!
    
    meanAccelPlate = mean(shakingData.dataPlate.Acceleration);
    meanAccelObject = mean(shakingData.dataObject.Acceleration);
    
    Tx = @(t) [1 0 0; 0 cos(t) -sin(t); 0 sin(t) cos(t)];
    Ty = @(t) [cos(t) 0 sin(t); 0 1 0; -sin(t) 0 cos(t)];
    Tz = @(t) [cos(t) -sin(t) 0; sin(t) cos(t) 0; 0 0 1];
    T_tot = @(r) Tx(r(1))*Ty(r(2))*Tz(r(3));
    
    objective = @(r,meanValues) max((T_tot(r)*meanValues-[0;0;9.81]).^2);
    
    anglesPlate = fminunc(@(r) objective(r,meanAccelPlate'),[0;0;0]);
    anglesObject = fminunc(@(r) objective(r,meanAccelObject'),[0;0;0]);
    
    shakingData.anglesSensorPlate = anglesPlate;
    shakingData.anglesSensorObject = anglesObject;
    
    transformedDataPlate = zeros(size(shakingData.dataPlate.Acceleration));
    transformedDataObject = zeros(size(shakingData.dataObject.Acceleration));
    
    for i=1:size(shakingData.dataPlate.Acceleration,1)
        transformedDataPlate(i,:) = T_tot(anglesPlate)*shakingData.dataPlate.Acceleration(i,:)';
        transformedDataObject(i,:) = T_tot(anglesObject)*shakingData.dataObject.Acceleration(i,:)';
    end
    
    shakingData.transformedDataPlate = transformedDataPlate;
    shakingData.transformedDataObject = transformedDataObject;
    
end

