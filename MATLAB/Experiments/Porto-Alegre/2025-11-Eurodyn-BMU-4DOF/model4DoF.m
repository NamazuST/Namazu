%Simple model for 4Dof steel frame (without rotational DoF, only translational)
n=4;                                    %Number of  DOF
m1=0.1122; m2=0.1122; m3=0.1122; m4=0.1122; %Mass parameters (measured mean values)
E=2.1e11; L=47.5e-3;h=0.45e-3;b=25.5e-3;I=b*h^3/12;
k1=12*E*I/L^3;
k2=k1; k3=k1; k4=k1; %Stiffness parameters (measured mean values) 
zetae=[0.0278 0.0663 0.0780 0.0880];   %Damping ratios (measured mean values)

K=[2*k1+2*k2   -2*k2        0.0      0.0; %Stiffenss matrix
     -2*k2     2*k2+2*k3   -2*k3     0.0;
      0.0      -2*k3      2*k3+2*k4 -2*k4
      0.0        0.0       -2*k4     2*k4];
M=[m1   0.0   0.0  0.0;  %Mass matrix
   0.0  m2    0.0  0.0;
   0.0  0.0   m3   0.0
   0.0  0.0   0.0  m4];
[Phi,Lambda]=eig(K,M);  
%Sorting ascending eigenvalues and eigenvectors
[temp,Index]=sort(diag(Lambda));
Lambda=diag(temp);                      %Matrix of Eigenvalues, Lambda sorted in ascending order    
Phi1(:,1:n)=Phi(:,Index(1:n));Phi=Phi1; %Sorting eigenvector
Omega=diag((temp).^0.5);                %Vector of Undamped mode frequencies (rad/s)
zeta=diag([zetae ones(1,n-length(zetae))]); %Damping ratios and, unmeasured ones assumed critically damped
C=M*Phi*(2*zeta*Omega)*Phi'*M;          %Damping matrix that matches given damping rations
%diag(Phi'*C*Phi)./diag(2*Omega)        %checking damping ratios

%Evaluate damped and undamped natural frequencies, damping rations
[Psi,e]=polyeig(K,C,M);      %Polynomial eigenvalue problem
wn=abs(e);                   %Natural frequencies (rad/s)
fn=abs(e)/(2*pi);            %Natural frequencies (Hz)
wd=imag(e);                  %Damped modal frequencies (rad/s)
fd=imag(e)/(2*pi);           %Damped modal frequencies (Hz)
zeta=-real(e)./abs(e);       %Damping ratio
%Sorting
[fn,Ix]=sort(fn);          
wn=wn(Ix);                   %Sorted natural frequencies (rad/s)
fd=fd(Ix);                   %Sorted damped frequencies (Hz)
wd=wd(Ix);                   %Sorted  damped frequencies (rad/s)
zeta=zeta(Ix);               %Sorted ramping ratios
Psi=Psi(:,Ix);               %Sorted eigenvectors

wn=wn(1:2:length(wn)-1);wn=wn(wn>0);   
fn=fn(1:2:length(fn)-1);fn=fn(fn>0);   

wd=wd(1:2:length(wd)-1);wd=wd(wd>0);   
fd=fd(1:2:length(fd)-1);fd=fd(fd>0);   

zeta=zeta(1:2:length(zeta)-1);
Psid=Psi(:,1:2:size(Psi,2)-1);  %Complex Eigenvectors

zp=[zeta(1);zeta(2);zeta(3)];   %Damping ratios

%Mean frequencies 
fprintf('Undamped Natural freq. (Hz):');fprintf('%+3.4f ',fn(1:n));fprintf('\n');
fprintf('Damped natural freq.   (Hz):');fprintf('%+3.4f ',fd(1:n));fprintf('\n');
fprintf('Damping ratios          (-):');fprintf('%+3.4f ',zeta(1:n));fprintf('\n');

%----FRF (Frequency response Functions)

nsl=2000; %number of spectral lines
nmode=n;
freq=linspace(0,5*fd(end),nsl);
w=linspace(0,5*wd(end),nsl);
mr=diag(Psid'*M*Psid);

%FRF Receptance  Hr=X(w)/F(w)
figure;
for i=1:n %Loop over DOF
   for j=i:n %Loop over DOF
       for insl=1:nsl
           summ=0.0;
           for imode=1:nmode
                summ=summ+Psid(i,imode)*Psid(j,imode)/((mr(imode)*(wd(imode)^2 - w(insl)^2 + 2*1i*zeta(imode)*wd(imode)^2)));
           end          
           Hr(insl,i,j)=summ;
       end
       Hr(:,j,i)=Hr(:,i,j);
       subplot(n,n,(i-1)*n+j),loglog(freq(:),abs(Hr(:,i,j)),'-k');grid on;title(['Hx_{',num2str(i),num2str(j),'}']);
       xlim([0 1.2*freq(end)]);xlabel('f [Hz]');ylabel(['Hx_{',num2str(i),num2str(j),'}',' [m/N]']);    
   end
end
sgtitle('Receptance Hr=X(w)/F(w)');

%FRF Mobility Hv=V(w)/F(w)=iw*X(w)/F(w)
figure;
for i=1:n %Loop over DOF
   for j=i:n %Loop over DOF
       for insl=1:nsl
           summ=0.0;
           for imode=1:nmode
                summ=summ+Psid(i,imode)*Psid(j,imode)*(1i*w(insl))/(((mr(imode)*(wd(imode)^2 - w(insl)^2 + 2*1i*zeta(imode)*wd(imode)^2))));
           end          
           Hv(insl,i,j)=summ;
       end
       Hv(:,j,i)=Hv(:,i,j);
       subplot(n,n,(i-1)*n+j),loglog(freq(:),abs(Hv(:,i,j)),'-k');grid on;title(['Hv_{',num2str(i),num2str(j),'}']);
       xlim([0 1.2*freq(end)]);xlabel('f [Hz]');ylabel(['Hv_{',num2str(i),num2str(j),'}',' [(m/s)/N]']);    
   end
end
sgtitle('Mobility Hv=V(w)/F(w)');

%FRF Acelerance Ha=A(w)/F(w)=-w^2*X(w)/F(w)
figure;
for i=1:n %Loop over DOF
   for j=i:n %Loop over DOF
       for insl=1:nsl
           summ=0.0;
           for imode=1:nmode
                summ=summ+Psid(i,imode)*Psid(j,imode)*(-w(insl)^2)/(((mr(imode)*(wd(imode)^2 - w(insl)^2 + 2*1i*zeta(imode)*wd(imode)^2))));
           end          
           Ha(insl,i,j)=summ;
       end
       Ha(:,j,i)=Ha(:,i,j);
       subplot(n,n,(i-1)*n+j),loglog(freq(:),abs(Ha(:,i,j)),'-k');grid on;title(['Ha_{',num2str(i),num2str(j),'}']);
       xlim([0 1.2*freq(end)]);xlabel('f [Hz]');ylabel(['Ha_{',num2str(i),num2str(j),'}',' [(m/s²)/N]']);    
   end
end
sgtitle('Acelerance Ha=A(w)/F(w)');

%Phase angle for receptance
figure;
 for i=1:n %Loop over DOF
    for j=i:n %Loop over DOF
        subplot(n,n,(i-1)*n+j),plot(freq(:),unwrap(angle(Hr(:,i,j)),2*pi)*180/pi,'-k');grid on;title(['\phi_{',num2str(i),num2str(j),'}','[º]']);
        xlim([0 1.2*freq(end)]);xlabel('f [Hz]');ylabel(['\phi_{',num2str(i),num2str(j),'}','[º]']);    
    end
 end
 sgtitle('Phase angle Hx');

 %----Transmissibility (load on first dof (a) and load on second dof(b))
figure;
for i=1:n %Loop over DOF
   for j=i+1:n %Loop over DOF
     Ta(:,i,j)=Hr(:,i,i)./Hr(:,j,i);Tb(:,i,j)=Hr(:,i,j)./Hr(:,j,j);
     subplot(n-1,n-1,(i-1)*(n-1)+j-1),loglog(freq(:),abs(Ta(:,i,j)),'-b');hold on;
     xlim([0 1.2*freq(end)]);xlabel('f [Hz]');ylabel(['T_{',num2str(i),num2str(j),'}^{a}','  [adm]']);grid on;hold off;
%     subplot(n-1,n-1,(i-1)*(n-1)+j-1),semilogy(freq(:),abs(Tb(:,i,j)),'-k');
%     xlim([0 1.2*freq(end)]);xlabel('f [Hz]');ylabel(['T_{',num2str(i),num2str(j),'}^{b}','  [adm]']);grid on;hold off;
   end
end
sgtitle('Transmissibility ')
