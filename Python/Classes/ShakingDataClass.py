import numpy as np
import os
from enum import Enum
import sys
from pathlib import Path
from NamazuInstance import NamazuInstance

###################################################################################################################################
# Signal Generation Method enumeration
###################################################################################################################################
class SignalGenerationMethod:
    NONE = "none"
    SHINOZUKA = "shinozuka"
    FIXED_HARMONIC = "fixed_harmonic"
    KANAI_TAJIMI = "kanai_tajimi"

###################################################################################################################################
# Class definition for the shaking data object
###################################################################################################################################

# super class for ShakingData, contains the basic attributes and methods for all types of shaking data, especially input signals and numerical differentiation
class ShakingData:
    def __init__(self, namazuInstance=None, sampleRate=100.0, maxT=10.0):
        self.inputSignal : np.ndarray = np.array([])
        self.inputVelocity : np.ndarray = np.array([])
        self.inputAcceleration : np.ndarray = np.array([])
        self.sampleRate : float = sampleRate
        self.marvCode : str = ""
        self.signalFiltered : bool = False 
        self.namazuInstance : NamazuInstance = namazuInstance
        self.maxT : float = maxT
###################################################################################################################################
    def setup(self):
        # Numerical differentiation to obtain speed and velocity values from the position signal
        # adds a 0 as an initial value for the first time step
        self.inputVelocity = np.column_stack([
            self.inputSignal[:, 0],
            np.hstack([0, np.diff(self.inputSignal[:, 1]) / np.diff(self.inputSignal[:, 0])])
        ])

        self.inputAcceleration = np.column_stack([
            self.inputSignal[:, 0],
            np.hstack([0, np.diff(self.inputVelocity[:, 1]) / np.diff(self.inputSignal[:, 0])])
        ])

        # Generate MarvCode if NamazuInstance is available
        if self.namazuInstance is not None:
            self.marvCode = self.WriteMarvCode()

    def WriteMarvCode(self):
    # Compiling marv code from positions and saving to the shakingData format

        form = 'add %5.4f\n'

        file_header = f'reset\nset spmm {self.namazuInstance.steps_per_mm}\nset rate {self.namazuInstance.motorRate}\n'
        cmd = file_header
        pos = self.inputSignal[:,1]

        for i in range(len(pos)):
            cmd += form % pos[i]

        return cmd
    
class FixedHarmonicShakingData(ShakingData):
    def __init__(self, namazuInstance=None, frequencies=1.0, amplitudes=1.0, sampleRate=100.0, maxT=10.0):
        super().__init__(namazuInstance, sampleRate, maxT)
        self.frequencies : list = []
        self.amplitudes : list = []

        if isinstance(frequencies, (int, float)):
            frequencies = [frequencies]
        if isinstance(amplitudes, (int, float)):
            amplitudes = [amplitudes]
        self.frequencies = frequencies
        self.amplitudes = amplitudes

    def generate_signal(self):
        # Simulate a fixed or mixed harmonic signal
        t_out = np.arange(0, self.maxT, 1/self.sampleRate)
        pos_out = np.zeros_like(t_out)

        for freq in self.frequencies:
            for amp in self.amplitudes:
                pos_out += amp * np.sin(2 * np.pi * freq * t_out)

        self.inputSignal = np.column_stack((t_out, pos_out))
        super().setup()

class ShinozukaShakingData(ShakingData):
    def __init__(self, namazuInstance=None, psd_func=None, sampleRate=100.0, maxT=10.0):
        super().__init__(namazuInstance, sampleRate, maxT)
        self.psd_func = psd_func