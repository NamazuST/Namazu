function [] = CompareSignals(s1,s2)

    signal1_ = s1;
    signal2_ = s2;
    
    Fs1 = ((signal1_(end,1)-signal1_(1,1))./length(signal1_(:,1)))^-1;
    Fs2 = ((signal2_(end,1)-signal2_(1,1))./length(signal2_(:,1)))^-1;
    
    [P,Q] = rat(Fs1/Fs2);    
    s2_ = resample(signal2_,P,Q);
    s1_ = signal1_;
    
    [s1_,s2_] = alignsignals(s1_(:,2),s2_(:,2));
    
    figure;hold on;
    plot(s2_);
    plot(s1_);
    
    maxlags = numel(s1_)*0.5;
    [xc,lag] = xcov(s1_,maxlags);  
    
    plot(lag,xc);

end

