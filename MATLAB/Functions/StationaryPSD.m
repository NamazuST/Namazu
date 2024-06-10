function p = StationaryPSD(signal, t)
%STATIONARYPSD
%Function to estimate the periodogram of a given signal

Nt = length(t);
dt = t(2) - t(1);
Nsamples = size(signal, 1);

p = zeros(1,Nt);
for i = 1:Nsamples
    p = p + abs(fft(signal(i,:))*dt).^2;
end

p = p / t(end) / Nsamples / (2*pi);

p = p(1:ceil(length(t)/2));

end