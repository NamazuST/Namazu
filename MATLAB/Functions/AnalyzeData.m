function [] = AnalyzeData(simulationData, lowpass_frequency)

% TODO: Write the data extraction methods (amplitude, time, fourier etc) as
% function of the simulationData-class so this code is not so fck ugly

    plotFiltered = 1;
    
    data1 = simulationData.dataPlate;
%     data2 = simulationData.dataObject;
    sampleRate = simulationData.sampleRate;

    t1 = zeros(length(data1.Time),1);
%     t2 = zeros(length(data2.Time),1);
    t1(2:end) = cumsum(seconds(diff(data1.Time)));
%     t2(2:end) = cumsum(seconds(diff(data2.Time)));

    alpha = 0.5;

    a1 = data1.Acceleration(:,1); %Plate
%     a2 = data2.Acceleration(:,1); %Model

    %First step of filtering to filter the mean deviation of acc (maybe
    %gravitation) "y-error"
    a1Filtered = a1-mean(a1);
    %second step to apply a lowpass filter
    a1Filtered = lowpass(a1Filtered, lowpass_frequency, sampleRate);
    
%     a2Filtered = a2;

%What is this?
%     for i=2:size(data1,1)
%         a1Filtered(i,:) = a1Filtered(i-1,:)*alpha+(1-alpha)*(a1(i,:)-a1(i-1,:));
% %         a2Filtered(i,:) = a2Filtered(i-1,:)*alpha+(1-alpha)*(a2(i,:)-a2(i-1,:));
%     end

    [amp1Filtered,f1Filtered] = fourier(a1Filtered,t1);
%     [amp2Filtered,f2Filtered] = fourier(a2Filtered,t2);

    [amp1,f1] = fourier(a1,t1); %Plate
%     [amp2,f2] = fourier(a2,t2); %Model

    v1Filtered = zeros(length(a1Filtered),1);
%     v2Filtered = zeros(length(a1Filtered),1);
    pos1Filtered = zeros(length(a1Filtered),1);
%     pos2Filtered = zeros(length(a1Filtered),1);

    for i=2:length(v1Filtered)
        v1Filtered(i) = v1Filtered(i-1) + a1Filtered(i-1)*(t1(i)-t1(i-1));
%         v2Filtered(i) = v2Filtered(i-1) + a2Filtered(i-1)*(t2(i)-t2(i-1));
        pos1Filtered(i) = pos1Filtered(i-1) + v1Filtered(i-1)*(t1(i)-t1(i-1));
%         pos2Filtered(i) = pos2Filtered(i-1) + v2Filtered(i-1)*(t2(i)-t2(i-1));
    end
    
%     [ampSim,fSim] = fourier(simulationData.inputSignal(:,2),simulationData.inputSignal(:,1));
    
    % fishy differentiation to obtain velocity and acceleration from the
    % position datatable 
    vel = diff(simulationData.inputSignal(:,2))./diff(simulationData.inputSignal(:,1));
    vel = [0;vel];
    acc = diff(vel)./diff(simulationData.inputSignal(:,1));
    acc(1) = 0;
    
    acc = acc/1000;
    vel = vel/1000;
    
    %Integrate measured acc to resemble displacements of the plate
%     vel_a1 = trapz(t1, a1);
%     disp_a1 = trapz(t1,vel_a1);
    
    % fourier transformation of the estimated acceleration
    [ampSim, fSim] = fourier(acc, simulationData.inputSignal(1:(end-2),1));

    [ampPos1,fPos1] = fourier(pos1Filtered,t1);
%     [ampPos2,fPos2] = fourier(pos2Filtered,t2);

    figure;
    subplot(2,1,1);
    hold on;
    if exist("fSim",'var') && exist("ampSim",'var')
        plot(fSim,ampSim./max(ampSim),'k--');
        plot(f1,amp1./max(amp1));
%         plot(f1,amp2./max(amp2));

        legend({'Sim','Plate'})%,'Model','Model Filtered'})
    else
        plot(f1,amp1./max(amp1));
%         plot(f2,amp2./max(amp2));
    end
    xlim([0,sampleRate/2]);
    xlabel("Frequency [Hz]");ylabel("relative Amplitude");

    subplot(2,1,2);
    hold on;
    if exist("fSim",'var') && exist("ampSim",'var')
        plot(fSim,ampSim,'k--');
        plot(f1,amp1);
%         plot(f2,amp2);
        legend({'Sim','Plate'})%,'Model','Plate Filtered','Model Filtered'})
    else
        plot(f1,amp1);
%         plot(f2,amp2);
        legend({'Plate','Model'});
    end
    xlim([0,sampleRate/2]);
    xlabel("Frequency [Hz]");ylabel("absolute Amplitude");
    
    if plotFiltered
        %PSD plot
        figure;
        subplot(2,1,1);
        plot(f1Filtered,amp1Filtered./max(amp1Filtered));
%         plot(f2Filtered,amp2Filtered./max(amp2Filtered));
        legend({'Plate Filtered'})%,'Model Filtered'});        
        ylabel("Relative amplitude");xlabel("Frequency [Hz]");
        
        subplot(2,1,2);
        plot(f1Filtered,amp1Filtered);
%        plot(f2Filtered,amp2Filtered);
        legend({'Plate Filtered'})%,'Model Filtered'});
        ylabel("Absolute amplitude");xlabel("Frequency [Hz]");
        
        %Time History plot of filtered signal
        %Normed
        figure
        %subplot(2,1,1);
        hold on
        plot(simulationData.inputSignal(1:end-1,1), acc(:)./max(abs(acc)))
        plot(t1-simulationData.motorStartupDelay, a1Filtered./max(abs(a1Filtered)))
        legend('normalized numeric acceleration derived from the input signal', 'normalized measured acceleration')
        %subplot(2,1,2)
        hold on;
        plot(simulationData.inputSignal(1:end-1,1), acc(:))
        plot(t1-simulationData.motorStartupDelay, a1Filtered)
        legend('acc input signal', 'acc measured (filtered)')
    end
    %% Benchmarking
    
    %Welche Einheiten werden hier rausgeschmissen und verglichen?
    Fehler1 = max(a1)-max(acc);
    disp('Fehler bei Beschleunigung')
    disp(num2str(Fehler1))
    
    time_vector = simulationData.inputSignal(:,1);
    a1_int = interp1(t1,a1, time_vector(1:end-1));
    
    l2error = norm(acc(1:end-1)-a1_int(1:end-1))./norm(acc(1:end-1));
    
    %Mit Normierung
    figure
    subplot(2,1,1);
    hold on
    plot(simulationData.inputSignal(1:end-1,1), acc(:)./max(abs(acc)))
    plot(t1-1, a1./max(abs(a1)))
    legend('normalized numeric acceleration derived from the input signal', 'normalized measured acceleration')
    subplot(2,1,2)
    hold on;
    plot(simulationData.inputSignal(1:end-1,1), acc(:))
    plot(t1-1, a1)
    legend('acc input signal', 'acc measured')
    
    %TODO: implement method specific benchmarks
    switch simulationData.simulationType
        case MethodEnum.FixedHarmonic
            % if only one frequency was used then compare the maximum
            % frequency of the estimated PSD (table motion) with the input
            % frequency
            [peaks_val, peaks_index] = findpeaks(amp1);
%             figure
%             plot(f1,amp1)
%             hold on
%             plot(f1(peaks_index),peaks_val, 'o')
            [max_vals, max_val_index] = max(amp1(2:end));
            f1(max_val_index+1)
    end
    
    
end

