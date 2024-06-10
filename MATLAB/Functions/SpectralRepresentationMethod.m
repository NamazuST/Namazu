function x_shnzk = SpectralRepresentationMethod(S, w, t)
%Function sampling a single stochastic process for a given frequency and
%time discretization as well as an anonymous Power Spectral Density
%function SRM, based on Shinozuka & Deodatis 1991.

tic_shnzk = tic;

Nt = length(t);
Nw = length(w);
dw = w(2)-w(1);

x_shnzk = zeros(1,Nt);

for w_n = 1:Nw
    
    if w(w_n) == 0
        A = 0;
    else
        A = sqrt(2*S(w(w_n))*dw);         
    end
    
    phi = rand*(2*pi);
    x_shnzk(1,:) = x_shnzk(1,:) + sqrt(2) * A * cos(w(w_n) * t + phi);
end

toc_shnzk = toc(tic_shnzk);
disp(['Shnzk elapsed time: ' num2str(toc_shnzk) 's'])

end