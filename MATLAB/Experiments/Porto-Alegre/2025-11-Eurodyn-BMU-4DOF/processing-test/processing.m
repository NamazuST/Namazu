%----------------------------------------------
%Post-processing of measured acceleration data
%----------------------------------------------
clc;clear all; close all; fclose all;
warning off;

%Measurement parameters
g=9.81;                       % Gravity acc. 9.81 m/s^2
setp=[0.0 0.0 0.0 0.0];       % Set point (in Volts) for each acc.
sens=[0.1072 0.1320 0.1276 0.1329]./g;  % Sensitivity in V/(m/s²) for each acc.
nchanel=length(sens);         %Number of measured channels
f1=fopen('results.txt','w');  %Open output file
%Programatically reading and processing acquired data
n_med=100;                      %Number of files to process
med_label=num2cell(1:n_med);  
level=0.03*ones(1,n_med);

%Import file options
opts = delimitedTextImportOptions("NumVariables", 2);
opts.Delimiter = ",";
opts.ExtraColumnsRule = "ignore";
opts.ConsecutiveDelimitersRule = "join";
opts.LeadingDelimitersRule = "ignore";
opts = setvaropts(opts, opts.VariableNames, "WhitespaceRule", "trim");
% Remove parentheses
opts = setvaropts(opts, opts.VariableNames, "TreatAsMissing", ["(", ")"]);

%Loop for data reading
iflag=1;          %flag to ploting[1] or not ploting[0] graphs
for i_med=[1:1]   %for batch processing, change to i_med=[1:100] 
    clear freqv zeta
    filename=strcat(strcat('teste_',num2str(i_med))); % Nome do arquivo a ser processado
    fprintf('Processing file No.: %s ...\n',filename);   
    % Converting to m/s²
    for icanal=1:4
        filenamech=strcat(strcat(strcat(filename,'_'),num2str(icanal)),'.dat');
        data=readmatrix(filenamech, opts);             % time(s) and acc.(V)
        data = str2double(erase(data, ["(", ")"])); %convert cell array of strings to numerical array
        time=data(:,1); acel=data(:,2); 
        dt=(time(2)-time(1));                      % time interval (s)      
        fs=1/dt;                                   % fs (Hz)
        T=time(end)-time(1);                       % Total measurement time (s)
        df=1/T;                                    % freqeuncy resolution (Hz)
        acc(:,icanal)=(acel-setp(icanal))./sens(icanal);    %Converting volts to m/s^2
        acc(:,icanal)=acc(:,icanal)-mean(acc(:,icanal));    % zero mean values
        arms(i_med,icanal)=rms(acel);                       % rms values
        temp=fft(acc(:,icanal))/(size(acc(:,icanal),1)/2);  % fft evaluation
        a_fft(:,i_med,icanal)=temp(1:round((size(acc(:,icanal),1)/2))); % fft evaluation
    end
    envfft=max([a_fft(:,i_med,1) a_fft(:,i_med,2) a_fft(:,i_med,3) a_fft(:,i_med,4)],[],2);
    maxvalue=max(abs(envfft));                % peak value 
    [pks,locs] = findpeaks(abs(envfft),'MinPeakHeight',level(i_med)*maxvalue,'MinPeakDistance',round(15/df)); %find peaks between maximum and minimum magnitude
    npks=max(nchanel,length(pks)); %number of peaks found
    
    freq=linspace(0,fs/2,round((size(data,1)/2)));   % frequency axis
    %graphs for time-history signals
    if iflag==1
        h1=figure;
        subplot(nchanel,nchanel,1);plot(time,acc(:,1),'-k');xlabel('Time [s]');ylabel('Acceleration [m/s²]');legend(['channel 1 rms: ' num2str(arms(i_med,1),'%5.4f')]);
        subplot(nchanel,nchanel,2);plot(time,acc(:,2),'-r');xlabel('Time [s]');ylabel('Acceleration [m/s²]');legend(['channel 2 rms: ' num2str(arms(i_med,2),'%5.4f')]);
        subplot(nchanel,nchanel,3);plot(time,acc(:,3),'-g');xlabel('Time [s]');ylabel('Acceleration [m/s²]');legend(['channel 3 rms: ' num2str(arms(i_med,3),'%5.4f')]);
        subplot(nchanel,nchanel,4);plot(time,acc(:,4),'-b');xlabel('Time [s]');ylabel('Acceleration [m/s²]');legend(['channel 4 rms: ' num2str(arms(i_med,4),'%5.4f')]);
        sgtitle(['Acceleration (m/s²) - Measurement #' num2str(med_label{i_med}) ' -']);
        %savefig(strcat(filename,'_tempo.fig'));
        %FFT grpahs for the signals
        subplot(nchanel,nchanel,nchanel+1);plot(freq,abs(a_fft(:,i_med,1)),'-k');xlabel('f [Hz]');ylabel('Acceleration [m/s²]');legend(['FFT 1']);xlim([0 100]);
        subplot(nchanel,nchanel,nchanel+2);plot(freq,abs(a_fft(:,i_med,2)),'-r');xlabel('f [Hz]');ylabel('Acceleration [m/s²]');legend(['FFT 2']);xlim([0 100]);
        subplot(nchanel,nchanel,nchanel+3);plot(freq,abs(a_fft(:,i_med,3)),'-g');xlabel('f [Hz]');ylabel('Acceleration [m/s²]');legend(['FFT 3']);xlim([0 100]);
        subplot(nchanel,nchanel,nchanel+4);plot(freq,abs(a_fft(:,i_med,4)),'-b');xlabel('f [Hz]');ylabel('Acceleration [m/s²]');legend(['FFT 4']);xlim([0 100]);
        drawnow;
        %savefig(strcat(filename,'_FFT.fig'));
        %---------------------------Peak Peaking-------------------------------
        %Select only the peaked values above 90% of maximum peak and separated by at least 15 Hz
        %Plot selected peaks for visual check
        subplot(nchanel,nchanel,2*nchanel+2);
        plot(freq,abs(envfft),'-k');xlabel('f [Hz]');ylabel('Acceleration [m/s²]');xlim([0 100]);
        hold on; plot(freq(locs),abs(envfft(locs)),'or');legend(['FFT Envelop', 'peak']);
    end
    
    %Define a delta_f around the peak fequencies and get the
    delta_f=5;npt=round(delta_f/df);
    %for each peak get frequencies around peak values, interpolate and get the maximum value
    for ipeak=1:length(pks)
        int_freq=linspace(freq(locs(ipeak)-npt),freq(locs(ipeak)+npt),5000);
        s=spline(freq(locs(ipeak)-npt:locs(ipeak)+npt),abs(envfft(locs(ipeak)-npt:locs(ipeak)+npt)),int_freq);
        %s=pchip(freq(locs(ipeak)-npt:locs(ipeak)+npt),abs(envfft(locs(ipeak)-npt:locs(ipeak)+npt)),int_freq);
        [pv,pp]=max(s);
        freqv(ipeak)=int_freq(pp);
    end    
    %----------------Damping ratio evaluation------------------------------
    %Filter signal around each peak frequency and evaluate damping ratio
    temp1=temp; %Channel 4 contains all natural frequencies
    for ipeak=1:length(pks)
        clear yuppern;
        temp=temp1;
        N2=round((size(acc(:,4),1)/2)); % metade do sinal no tempo
        temp(1:locs(ipeak)-npt)=0;temp(locs(ipeak)+npt:end)=0;
        acc_filt=real(ifft(temp*round(size(acc(:,icanal),1)/2)));
        [V,I]=max(acc_filt);
        %--------------        
        delta_ti=1*(1/freqv(ipeak));  %intervalo de tempo em segundos para depois do pico do sinal no tempo, avaliar o decremento
        delta_tf=30*(1/freqv(ipeak)); %intervalo de tempo em segundos para para avaliar o decremento
        mm=round(delta_ti/dt);
        nn=round(delta_tf/dt);        
        if iflag==1
            subplot(nchanel,nchanel,3*(nchanel)+ipeak);hold on;
            plot(time,acc_filt,'-k');xlabel('Time [s]');ylabel('Filtered acceleration [m/s²]');
            xlim([(I+mm)*dt (I+nn)*dt]);
            %plot(time(I),acc_filt(I),'or');
        end
        %[yupper,ylower] = envelope(acc_filt(I+mm:I+nn),round((1/freqv(ipeak))/dt),'peak');
        [yupper,~] = envelope(acc_filt(I+mm:I+nn),500,'analytic');
        yuppern=yupper(10:end);
        if iflag==1
            plot(time(I+mm+9:I+nn),yuppern(:),'-b');
        end
        %Adjust the exponential decrement to the experimental envelop
        sse =@(lambda) sum((yupper(:) - yupper(1)*exp(-lambda*(time(I+mm:I+nn)-time(I)))).^2);
        lambda0=0.001; %first guess for optimization 
        lambda = fminsearch(sse,lambda0);
        zeta(ipeak)=lambda/(2*pi*freqv(ipeak));
        if iflag==1
            plot(time(I+mm:I+nn),yupper(1)*exp(-lambda*(time(I+mm:I+nn)-time(I))),'-r');
        end
    end
    fprintf('Sample:%3i  freq(Hz):',i_med);
    fprintf(' %+5.8f',freqv(1:length(pks)));
    fprintf(' zeta(-): ')
    fprintf(' %+5.8f',zeta(1:length(pks)));fprintf('\n')
    fprintf(f1,' %3i',i_med);fprintf(f1,' %+5.8f',freqv);fprintf(f1,' %+5.8f',zeta);fprintf(f1,' \n');
    freqsample(i_med,:)=freqv(1:length(pks));
    zetasample(i_med,:)=zeta(1:length(pks));
end
fclose(f1);

