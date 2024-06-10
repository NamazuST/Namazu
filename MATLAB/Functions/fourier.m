function [amp,f] = fourier(Y,t)
    
    Y = fft(Y);
    L=length(t);
    Fs = 1/(t(2)-t(1));
    P2 = abs(Y/L);
    amp = P2(1:L/2+1);
    amp(2:end-1) = 2*amp(2:end-1);
    f = Fs*(0:(L/2))/L;
    
end