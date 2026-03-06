import numpy as np
import matplotlib.pyplot as plt
from Classes.NamazuInstance import NamazuInstance
from Classes.ShakingDataClass import *

def main():
    namazu = NamazuInstance("COM5")
    namazu.connect()
    print("Motor rate: ", namazu.motorRate)

    simulation = FixedHarmonicShakingData(namazu,
                                          frequencies=2.0,
                                          amplitudes=5.0,
                                          maxT=100.0)
    print(type(simulation))

    simulation.generate_signal()

    # print(simulation.marvCode)

    # plt.plot(simulation.inputSignal[:, 0], simulation.inputSignal[:, 1])
    # plt.title("Fixed Harmonic Signal")
    # plt.xlabel("Time [s]")
    # plt.ylabel("Amplitude")
    # plt.show()

    namazu.send_command(simulation.marvCode)

    namazu.disconnect()

if __name__ == "__main__":
    print("Hello Namazu!")
    main()