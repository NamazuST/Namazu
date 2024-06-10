###################################################################################################################################
#Test function for the serial connection to the ESP32
###################################################################################################################################
#First make sure pyserial is installed
#pip install pyserial

import serial
import time

# Set the COM port and baud rate according to your ESP32 configuration
com_port = 'COM3'  # Change this to your COM port on Windows, e.g., 'COM3'
baud_rate = 921600  # Change this to match your ESP32 configuration

# Open the serial connection
ser = serial.Serial(com_port, baud_rate, timeout=1)

# Flush any existing data in the input buffer
ser.flushInput()

# Send a command to the ESP32
command = "info"
ser.write(command.encode() + b'\n')  # Add newline character at the end

time.sleep(0.1)  # Wait a bit for the device to respond

# Read the response from the ESP32
response = ser.readline().decode().strip()  # Decode bytes to string and remove trailing newline
print(f"Response from ESP32: {response}")

# Close the serial connection when done
ser.close()