###################################################################################################################################
#Main script to simulate and send a fixed or mixed harmonic signal based to the ESP32 -> Driver -> Motor
#Import shaking data object
from Classes import ShakingDataClass
#Import Namazu framework functions
from Methods import InputSignalMethods
from Functions import WriteMarvCode
from Functions import SendCode2Motor
#Import utilities
import matplotlib.pyplot as plt

# Create an instance of the ShakingData class
shaking_data_instance = ShakingDataClass.ShakingData()

#Simulation parameters
stepsPerSecond = 100    #Steps performed per second
shaking_data_instance.motorRate = stepsPerSecond
maxT = 5               #Maximum number of time for the simulation  
inputFrequency_val = 1  #desired input frequency or frequencies
#inputFrequency_val = [2, 8]  #desired input frequencies
inputAmp_val = 1        #desired input amplitude
#inputAmp_val = [1, 3]        #desired input amplitude

#Simulate a fixed or mixed harmonic signal
[pos_out, t_out, shaking_data_instance] = InputSignalMethods.SimulateFixedHarmonic(shaking_data_instance, inputFrequency_val, inputAmp_val, maxT, stepsPerSecond)

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