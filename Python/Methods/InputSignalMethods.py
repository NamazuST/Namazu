import numpy as np
from Functions.SpectralRepresentationMethod import SpectralRepresentationMethod
###################################################################################################################################
#Collection of possible input signal generation methods
###################################################################################################################################

#Simulate a fixed or mixed harmonic signal
def SimulateFixedHarmonic(shaking_data_instance, inputFrequency, inputAmp, SimTime, NstepsPerSecond):

    #Check for the number of harmonics
    if hasattr(inputFrequency, "__len__"):
        Nomega = len(inputFrequency)
    else:
        Nomega = 1

    #construct time vector
    t =  np.linspace(0,SimTime,int(SimTime/(1/NstepsPerSecond)))

    #extract dt
    dt = t[1]-t[0]

    #chars for naming convention
    omName = 'om_'
    ampName = 'amp_'

    #Simple calculation if there is only one frequency
    if Nomega == 1:
        if isinstance(inputFrequency, list):
            inputFrequency = inputFrequency[0]
            inputAmp = inputAmp[0]
            
        #simulate the harmonic
        pos = inputAmp * np.sin((inputFrequency*2.*np.pi) * t)
        #concentate the name char
        name = omName + str(inputFrequency) + '_' + ampName + str(inputAmp) + '_' + str(SimTime) + '_' + str(NstepsPerSecond)
    else:
        #initialize position vector
        pos = np.zeros(len(t));
        #summation over desired frequencies
        for i in range(0,Nomega):
            pos = pos + inputAmp[i] * np.sin(inputFrequency[i] * 2 * np.pi * t)           
            omName = omName + str(inputFrequency[i]) + '_'
            ampName = ampName + str(inputAmp[i]) + '_'
        
        name = omName + ampName + str(SimTime) + '_' + str(NstepsPerSecond)

    # Define output file name
    shaking_data_instance.fileName = f"Harmonic_{name}"

    return [pos, t, shaking_data_instance]
###################################################################################################################################
#Signal generation for the Shinozuka Benchmark
def SimulateShinozukaBenchmark(*args):
    if len(args) > 2:
        raise ValueError("check variable input arguments for SimulateShinozukaBenchmark")
    else:
        if args:
            amplitude_scaling_factor = args[0]
            print(f"Shinozuka Benchmark is scaled by a factor of {amplitude_scaling_factor}")
            shaking_data_instance = args[1]
        else:
            amplitude_scaling_factor = 1
    
    # Parameter Shinozuka example (Shinozuka & Deodatis 1991)
    wl = 0  # Starting frequency
    wu = 4 * np.pi  # Cutoff frequency
    maxT = 64  # Maximum time
    dt = np.pi / wu  # Time increment (delta T)
    shaking_data_instance.motorRate = 1/dt  # Steps performed per second
    dw = 2 * np.pi / maxT  # Omega increment (delta Omega)

    t = np.arange(0, maxT, dt)  # Time discretisation
    w = np.arange(wl, wu, dw)  # Omega discretisation

    # Continuous Power Spectral Density (PSD) related Parameters
    sigma = 1  # Standard deviation of in the end, generated signal
    b = 1

    def S_function(omega):
        return 0.25 * sigma**2 * b**3 * omega**2 * np.exp(-b * np.abs(omega))

    # Shinozuka
    pos = SpectralRepresentationMethod(S_function, w, t)

    # Crude scaling of the signal
    pos *= amplitude_scaling_factor

    # PSD estimation using FFT
    p_shnzk = StationaryPSD(pos, t)

    name = f"scale_{amplitude_scaling_factor}"

    # Define output file name
    shaking_data_instance.fileName = f"Shinozuka_Bechmark_scale_{amplitude_scaling_factor}"

    return pos, t, dt, maxT, shaking_data_instance
###################################################################################################################################
#Signal generation for the Shinozuka Benchmark
def SimulateShinozuka(shaking_data_instance, SimTime, maxFrequency, nOmega):

    #Steps per Seconds is derived from the motor rate
    NstepsPerSecond = shaking_data_instance.motorRate

    #construct time vector
    t =  np.linspace(0,SimTime,int(SimTime/(1/NstepsPerSecond)))
    #construct omega frequency vector
    w = np.linspace(0,maxFrequency,nOmega)

    # Shinozuka
    pos = SpectralRepresentationMethod(shaking_data_instance.psdFunc, w, t)

    return pos, t, t[1], shaking_data_instance

###################################################################################################################################
#Periodogram estimation of the Power Spectral Density (PSD)
def StationaryPSD(signal, t):
    dt = t[1] - t[0]

    p = np.abs(np.fft.fft(signal) * dt)**2

    p /= t[-1] * (2 * np.pi)

    p = p[:int(np.ceil(len(t) / 2))]

    return p