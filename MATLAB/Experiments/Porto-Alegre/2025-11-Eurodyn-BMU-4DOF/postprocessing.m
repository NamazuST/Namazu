%-------------------
% PostProcessing data to obtain PDF and correlations
%-------------------
filename='results.txt';
data=readmatrix(filename);
freqexp=data(:,2:5); zetaexp=data(:,6:9); 
%Mean values
nchanel=size(freqexp,2);
for ichanel=1:nchanel
    fprintf('f(%1i)    Mean=%3.6f (Hz) StdDev=%3.6f CoV=%3.6f   ',ichanel,mean(freqexp(:,ichanel)),std(freqexp(:,ichanel)),std(freqexp(:,ichanel))/mean(freqexp(:,ichanel)));
    fprintf('zeta(%1i) Mean=%3.6f  (-) StdDev=%3.6f CoV=%3.6f \n',ichanel,mean(zetaexp(:,ichanel)),std(zetaexp(:,ichanel)),std(zetaexp(:,ichanel))/mean(zetaexp(:,ichanel)));
end

%Plot dispersion of data
figure;
for ipeaks=1:4
    subplot(2,nchanel,ipeaks);
    histogram(freqexp(:,ipeaks), 'Normalization', 'pdf'); 
    hold on;
    %Kernel Density Estimation    
    [x_pdf, f_pdf] = ksdensity(freqexp(:,ipeaks)); % Evaluate the kernel density
    plot(f_pdf, x_pdf,  'r', 'LineWidth', 2); % Plot KDE    
    xlabel('Data'); ylabel('Frequency PDF');
    title('Histogram with KDE');
    legend('Histogram','KDE');
    grid on;

    subplot(2,nchanel,nchanel+ipeaks);
    histogram(zetaexp(:,ipeaks), 'Normalization', 'pdf'); 
    hold on;
    %% Kernel Density Estimation    
    [x_pdf, f_pdf] = ksdensity(zetaexp(:,ipeaks)); % Evaluate the kernel density
    plot(f_pdf, x_pdf,  'r', 'LineWidth', 2); % Plot KDE    
    xlabel('Data'); ylabel('Damping ratio PDF');
    title('Histogram with KDE');
    legend('Histogram','KDE');
    grid on;
end

Te=[freqexp zetaexp]';
nsamp=size(Te,2);
%Plot frequency clouds and confidence ellipses
h1=figure;
ntp=1;  %Type of plot (1=confidence elipsis 2=box envelope)
op=1;   %Options to calculate the covariance (1=Eigenvalue factorization 2=Lu factorzation)
P=[0.682 0.954 0.997];   %Confidence interval for each contour (Probability
nc=30;                   %Number of points to create the countours
no=size(Te,2);           %Number of outputs
noi=1;                   %Initial number of the output vector
noo=4;                   %Final number of the output vector
%Calculate mean values for synthetic experimental and numerical outputs
for i=noi:noo
   Temean(i,1)=mean(Te(i,:));
end
for i=noi:noo
    for j=i+1:noo        
        thetaemean=[Temean(i);Temean(j)];
        if ntp==1    %Plot of confidence ellipses
            Tevar=[Te(i,:); Te(j,:)];
            thetaeCov=cov(Tevar');  %Calculate the covariance matrix: each row is a realisation each column is a RV
            if op==1
                [V,D]=eig(thetaeCov);   %eigenvalue-eigenvector decomposition

            else if op==2
                L=chol(thetaeCov,'lower');   %Cholesky factorization (get the lower triangular!!!not the upper!!)
                end
            end
        else
            Terec=[min(Te(i,:)) min(Te(j,:)) (max(Te(i,:))-min(Te(i,:))) (max(Te(j,:))-min(Te(j,:)))];
        end
        h=subplot(noo-noi,noo-noi,((i-noi+1)-1)*((noo-noi)-1)+((j-noi+1)-1));
        %Plot experimental values
        plot(Te(i,:),Te(j,:),'bo','MarkerFaceColor','white','MarkerSize',4);hold on;
        plot(Temean(i),Temean(j),'bp','MarkerEdgeColor','blue',... 
                                 'MarkerFaceColor','white',...
                                 'MarkerSize',10);%Plot experimental mean value
        set(h,'FontSize',10,'Fontname','Times New Roman');
        xlabel({['\it{f}\rm_',num2str(i),' (Hz)']},'FontSize',12,'Fontname','Times New Roman');ylabel({['\it{f}\rm_',num2str(j),' (Hz)']},'FontSize',12,'Fontname','Times New Roman');
        leg=legend(['Exp.(',num2str(nsamp),' samp.)'],'AutoUpdate','off');set(leg,'FontSize',8,'Fontname','Times New Roman');
        if ntp==1    %Plot of confidence ellipses
            for k=1:size(P,2)
                %Define de confidence interval (percentual of experim. data contained in the interval)
                alfa=sqrt(-2*log(1-P(1,k)));  %Define the radius of circle in the uncorrelated space
                beta=linspace(0.0,2*pi,nc);   %Define the angular variable to draw
                y1=alfa*cos(beta);y2=alfa*sin(beta);
                %Transform to the original space
                if op==1
                    thetae=repmat(thetaemean,1,nc)+(V*diag(diag(D).^0.5))*[y1' y2']';
                else if op==2
                    thetae=repmat(thetaemean,1,nc)+L*[y1' y2']';  
                    end
                end
                plot(thetae(1,:),thetae(2,:),'-','Color','blue','LineWidth',0.01);
                %text(thetae(1,round(nc/3)),thetae(2,round(nc/3)),num2str(P(k)),'Color','blue','FontSize',8,'Fontname','Times New Roman');
                text(thetae(1,round(nc/6)),thetae(2,round(nc/6)),{[num2str(k),'\sigma']},'Color','blue','FontSize',8,'Fontname','Times New Roman');                
            end
            
            %plot the two orthogonal axes
            alfa=1.2*sqrt(-2*log(1-P(1,size(P,2))));%Increase 20% the radius of circle of last confidence interval
            beta=[0  pi  3*pi/2 pi/2   ];   %Define the angular variable to draw
            y1=alfa*cos(beta);y2=alfa*sin(beta);           
            if op==1
                thetae=repmat(thetaemean,1,4)+(V*diag(diag(D).^0.5))*[y1' y2']';
                plot(thetae(1,1:2),thetae(2,1:2),'Color','k'); %Axis 'y1'
                plot(thetae(1,3:4)',thetae(2,3:4)','Color','k'); %Axis 'y2'
            else if op==2
                thetae=repmat(thetaemean,1,4)+L*[y1' y2']'; 
                plot(thetae(1,1:2),thetae(2,1:2),'Color','k'); %Axis 'y1'
                l=sqrt((thetae(1,4)-thetae(1,3))^2+(thetae(2,4)-thetae(2,3))^2);
                beta=atan((thetae(2,2)-thetae(2,1))/(thetae(1,2)-thetae(1,1)))+pi/2;
                x1=l*cos(beta);y1=l*sin(beta);
                thetae(1,3)=thetaemean(1)+x1/2;thetae(1,4)=thetaemean(1)-x1/2;
                thetae(2,3)=thetaemean(2)+y1/2;thetae(2,4)=thetaemean(2)-y1/2;
                plot(thetae(1,3:4),thetae(2,3:4),'Color','k'); %Axis 'y2'
                end
            end
        else
            rectangle('Position',Terec,'edgecolor','b');
        end
        axis equal;
    end
end
%Plot in the three axis
h2=figure;
for i=1:1
    hold on;grid on;%axis equal
    plot3(Te(i,:),Te(i+1,:),Te(i+2,:),'bp','MarkerFaceColor','white','MarkerSize',5);%Plot experimental values
    plot3(Temean(i),Temean(i+1),Temean(i+2),'bp','MarkerEdgeColor','blue','MarkerFaceColor','white','MarkerFaceColor','blue','MarkerSize',8);%Plot experimental mean value);
    xlabel({['\it{f}\rm_',num2str(i  ),' (Hz)']},'FontSize',12,'Fontname','Times New Roman');
    ylabel({['\it{f}\rm_',num2str(i+1),' (Hz)']},'FontSize',12,'Fontname','Times New Roman');
    zlabel({['\it{f}\rm_',num2str(i+2),' (Hz)']},'FontSize',12,'Fontname','Times New Roman');
    leg=legend(['Exp.(',num2str(nsamp),' samp.)'],['\it{\mu}_m ']);set(leg,'FontSize',8,'Fontname','Times New Roman');
end