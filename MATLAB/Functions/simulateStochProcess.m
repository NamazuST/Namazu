function [f] = simulateStochProcess(S,maxOmega,tVec,nOmega,N)
%Function sampling a single stochastic process for a given maximum frequency, the 
%number of desired frequency discretisation points and
%time discretization as well as an anonymous Power Spectral Density
%function S
%also (as SpectralRepresentationMethod) based on Shinozuka & Deodatis 1991.
%However, here a linear fixed frequency discretization is assumed.

    
    omega = linspace(0,maxOmega,nOmega)';
    f = zeros(N,length(tVec));
    A = zeros(length(omega),1);
    
    for Aind=1:length(omega)
        A(Aind) = sqrt(2*S(omega(Aind))*(omega(2)-omega(1)));
    end

    r_ = rand(length(omega),N);
    for n=1:N
        f(n,:) = sum(A.*cos(omega*tVec+r_(:,n)*2*pi),1)*sqrt(2);
    end

end