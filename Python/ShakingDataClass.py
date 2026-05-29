import numpy as np
import os
from enum import Enum
import sys
from pathlib import Path
from NamazuInstance import NamazuInstance
from dataclasses import dataclass, field
from typing import Any, List, Literal

###################################################################################################################################
# Signal Generation Method enumeration
###################################################################################################################################
class SignalGenerationMethod:
    NONE = "none"
    SHINOZUKA = "shinozuka"
    FIXED_HARMONIC = "fixed_harmonic"
    FREQUENCY_SWEEP = "frequency_sweep"

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
        self.signalFiltered : bool = True 
        self.namazuInstance : NamazuInstance = namazuInstance
        self.maxT : float = maxT
###################################################################################################################################
    def setup(self):
        # Numerical differentiation to obtain speed and velocity values from the position signal
        # adds a 0 as an initial value for the first time step

        if self.signalFiltered:
            self.filter_signal(1.0, 0.5)
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
    
    def filter_signal(self, start: float, end: float):
        # Apply linear fade at start seconds and (maxT - end) seconds to avoid discontinuities in the signal
        if self.inputSignal.size == 0:
            raise ValueError("Input signal is empty. Cannot filter signal.")
        
        if start < 0 or end < 0 or start + end >= self.maxT:
            raise ValueError("Start and end times must be within the range of the signal duration.")

        weights = np.ones(len(self.inputSignal))
        mask_start = self.inputSignal[:, 0] < start
        mask_end = self.inputSignal[:, 0] > (self.maxT - end)

        if start > 0:
            weights[mask_start] = np.linspace(0, 1, sum(mask_start))
        
        if end > 0:
            weights[mask_end] = np.linspace(1, 0, sum(mask_end))

        print(weights)
        print(weights.shape)

        print(self.inputSignal)
        print(self.inputSignal.shape)
        
        self.inputSignal[:, 1] = self.inputSignal[:, 1] * weights

        print(self.inputSignal)
        print(self.inputSignal.shape)
    
@dataclass
class ParameterDefinition:
    """Describes a single user-configurable parameter for a ShakingData subclass."""
    name: str                          # internal key, used as constructor kwarg
    label: str                         # display label in the UI
    type: Literal["float", "int", "str", "float_list", "choice"]
    default: Any
    choices: List[str] = field(default_factory=list)  # only for type="choice"
    unit: str = ""                     # optional unit shown next to label

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

    @classmethod
    def get_parameter_definitions(cls) -> List[ParameterDefinition]:
        return [
            ParameterDefinition("frequencies", "Frequencies", "float_list", "1.0",  unit="Hz"),
            ParameterDefinition("amplitudes",  "Amplitudes",  "float_list", "5.0",  unit="mm"),
        ]

    @classmethod
    def from_params(cls, params: dict, namazu_instance, sample_rate: float, max_t: float):
        return cls(
            namazuInstance=namazu_instance,
            frequencies=params["frequencies"],
            amplitudes=params["amplitudes"],
            sampleRate=sample_rate,
            maxT=max_t,
        )


class ShinozukaShakingData(ShakingData):
    def __init__(self, namazuInstance=None, omega_g=15.0, zeta_g=0.6, 
                 psd_type="Kanai-Tajimi", sampleRate=100.0, maxT=10.0):
        super().__init__(namazuInstance, sampleRate, maxT)
        self.omega_g = omega_g
        self.zeta_g = zeta_g
        self.psd_type = psd_type
        # Build the psd_func from parameters
        if psd_type == "Kanai-Tajimi":
            self.psd_func = lambda w: self._kanai_tajimi_psd(w, omega_g, zeta_g)
        else:
            self.psd_func = None  # placeholder for custom

    @staticmethod
    def _kanai_tajimi_psd(omega, omega_g, zeta_g, S0=1.0):
        """Kanai-Tajimi power spectral density."""
        num = 1 + (2 * zeta_g * omega / omega_g) ** 2
        den = (1 - (omega / omega_g) ** 2) ** 2 + (2 * zeta_g * omega / omega_g) ** 2
        return S0 * num / den

    def generate_signal(self):
        if self.psd_func is None:
            raise NotImplementedError("No PSD function defined for this configuration.")
        dw = 2 * np.pi / self.maxT
        w = np.arange(dw, 10 * self.omega_g, dw)
        t = np.arange(0, self.maxT, 1 / self.sampleRate)
        pos = SpectralRepresentationMethod(self.psd_func, w, t)
        self.inputSignal = np.column_stack((t, pos))
        super().setup()

    @classmethod
    def get_parameter_definitions(cls) -> List[ParameterDefinition]:
        return [
            ParameterDefinition("omega_g", "Ground frequency ωg", "float", "15.0", unit="rad/s"),
            ParameterDefinition("zeta_g",  "Damping ratio ζg",    "float", "0.6"),
            ParameterDefinition("psd_type","PSD Type",            "choice","Kanai-Tajimi",
                                choices=["Kanai-Tajimi", "Custom"]),
        ]

    @classmethod
    def from_params(cls, params: dict, namazu_instance, sample_rate: float, max_t: float):
        return cls(
            namazuInstance=namazu_instance,
            omega_g=params["omega_g"],
            zeta_g=params["zeta_g"],
            psd_type=params["psd_type"],
            sampleRate=sample_rate,
            maxT=max_t,
        )


def SpectralRepresentationMethod(S, w, t):
    Nt = len(t)
    Nw = len(w)
    dw = w[1] - w[0]
    
    x_shnzk = np.zeros(Nt)
    
    for w_n in range(Nw):
        if w[w_n] == 0:
            A = 0
        else:
            A = np.sqrt(2 * S(w[w_n]) * dw)
        
        phi = np.random.rand() * (2 * np.pi)
        x_shnzk += np.sqrt(2) * A * np.cos(w[w_n] * t + phi)
    
    return x_shnzk

class FrequencySweepShakingData(ShakingData):
    def __init__(self, namazuInstance=None, f_start=0.1, f_end=10.0, amplitude=1.0,sampleRate=100.0, maxT=10.0):
        super().__init__(namazuInstance, sampleRate, maxT)
        self.f_start = f_start
        self.f_end = f_end
        self.amplitude = amplitude

    def generate_signal(self):
        t = np.arange(0, self.maxT, 1 / self.sampleRate)
        k = (self.f_end - self.f_start) / self.maxT
        pos = self.amplitude * np.sin(2 * np.pi * (self.f_start * t + 0.5 * k * t**2))
        self.inputSignal = np.column_stack((t, pos))
        super().setup()

    @classmethod
    def get_parameter_definitions(cls) -> List[ParameterDefinition]:
        return [
            ParameterDefinition("f_start", "Start frequency f_start", "float", "0.1", unit="Hz"),
            ParameterDefinition("f_end", "End frequency f_end", "float", "10.0", unit="Hz"),
            ParameterDefinition("amplitude", "Amplitude", "float", "1.0", unit="mm"),
        ]

    @classmethod
    def from_params(cls, params: dict, namazu_instance, sample_rate: float, max_t: float):
        return cls(
            namazuInstance=namazu_instance,
            f_start=params["f_start"],
            f_end=params["f_end"],
            amplitude=params["amplitude"],
            sampleRate=sample_rate,
            maxT=max_t,
        )