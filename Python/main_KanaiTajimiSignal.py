###################################################################################################################################
#Main script to simulate and send a stochastic signal based on the Kanai-Tajimi Spectrum to the ESP32 -> Driver -> Motor
#Import shaking data object
from Classes import ShakingDataClass
#Import Namazu framework functions
from Methods import InputSignalMethods
from Functions import WriteMarvCode
from Functions import SendCode2Motor
#Import utilities
import matplotlib.pyplot as plt
import numpy as np

# Create an instance of the ShakingData class
shaking_data_instance = ShakingDataClass.ShakingData()

#Simulation parameters
stepsPerSecond = 100    #Steps performed per second
shaking_data_instance.motorRate = stepsPerSecond
maxT = 5               #Maximum number of time for the simulation in seconds
maxF = 12              #Maximum frequency
nOmega = 50            #Number of discretized frequencies
# Kanai-Tajimi scale parameters
w_g = 9 * 2 * np.pi  # Peak frequency
beta_g = 0.6
# Scale whole PSD function amplitude
S_0 = 0.01

# Define the PSD function
def PSD_KT(omega):
    numerator = (w_g ** 4 + (2 * beta_g * w_g * omega) ** 2)
    denominator = ((w_g ** 2 - omega ** 2) ** 2 + (2 * beta_g * w_g * omega) ** 2)
    return numerator / denominator * S_0

# Store the PSD function for later access
shaking_data_instance.psdFunc = PSD_KT

# Define output file name
shaking_data_instance.fileName = f"Shinozuka_Kanai-Tajimi_{maxF}_{nOmega}_{maxT}_{stepsPerSecond}"

#Simulate a fixed or mixed harmonic signal
[pos_out, t_out, dt_out, shaking_data_instance] = InputSignalMethods.SimulateShinozuka(shaking_data_instance, maxT, maxF*2*np.pi, nOmega)

# Create a line plot for one frequency
plt.plot(t_out, pos_out)
# displaying the title
plt.title(shaking_data_instance.fileName)
plt.xlabel("time in [s]")
plt.ylabel("x in [mm]")

# Show the plot
plt.show()

#Store the input signal in the shaking data object
shaking_data_instance.inputSignal= [t_out, pos_out]

#Write the marvCode
shaking_data_instance = WriteMarvCode.WriteMarvCode(shaking_data_instance)

#This needs to be send to the ESP32
import serial # pyserial is required
import time

# Set the COM port and baud rate according to your ESP32 configuration
com_port = 'COM3'  # Change this to your COM port on Windows, e.g., 'COM3'
baud_rate = 921600  # Change this to match your ESP32 configuration

# Open the serial connection
ser = serial.Serial(com_port, baud_rate, timeout=1)
# Flush any existing data in the input buffer
ser.flushInput()

# Send the marvCode (displacement history) to ESP32
SendCode2Motor.SendMarvCode2Motor(ser, shaking_data_instance)

prompt_response = input("To continue, press 'y': ")
if prompt_response.lower() == 'y':
    print("Continuing...")
    # Start the motor
    SendCode2Motor.SendCmd2Motor(ser, 'start')
    time.sleep(t_out[-1]+5)  # Wait for T+5 seconds
else:
    print("Not continuing.")

# Close port
print("Shaking finished. Closing port...")
ser.close()
print("Port closed.")