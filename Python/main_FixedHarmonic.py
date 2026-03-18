###################################################################################################################################
#Main script to simulate and send a fixed or mixed harmonic signal based to the ESP32 -> Driver -> Motor
#Import shaking data object
from Classes import ShakingDataClass
#Import Namazu framework functions
from Methods import InputSignalMethods
from Functions import WriteMarvCode
from Functions import SendCode2Motor
#Import utilities
# import matplotlib.pyplot as plt
import serial # pyserial is required
import time

class FixedHarmonic():
    def __init__(self, stepsPerSecond=100, maxT=5, com_port='COM3', baud_rate=921600):
        # Create an instance of the ShakingData class
        self.shaking_data_instance = ShakingDataClass.ShakingData()
        #Simulation parameters
        self.stepsPerSecond = stepsPerSecond    #Steps performed per second
        self.shaking_data_instance.motorRate = self.stepsPerSecond
        self.maxT = maxT               #Maximum number of time for the simulation  
        self.inputFrequency_val = 1  #desired input frequency or frequencies
        #inputFrequency_val = [2, 8]  #desired input frequencies
        self.inputAmp_val = 1        #desired input amplitude
        #inputAmp_val = [1, 3]        #desired input amplitude
        self.com_port = com_port  
        self.baud_rate = baud_rate

    def update_data(self, stepsPerSecond, maxT, inputFrequency_val, inputAmp_val):
        self.stepsPerSecond = stepsPerSecond
        self.maxT = maxT
        self.inputFrequency_val = inputFrequency_val
        self.inputAmp_val = inputAmp_val

    def simulate_input_signal(self):
        [pos_out, t_out, self.shaking_data_instance] = InputSignalMethods.SimulateFixedHarmonic(self.shaking_data_instance, 
            self.inputFrequency_val, self.inputAmp_val, self.maxT, self.stepsPerSecond)
        return pos_out, t_out, self.shaking_data_instance

    def write_marv_code(self):
        self.pos_out, self.t_out, self.shaking_data_instance = self.simulate_input_signal()
        self.shaking_data_instance.inputSignal = [self.t_out, self.pos_out]
        self.shaking_data_instance = WriteMarvCode.WriteMarvCode(self.shaking_data_instance)

    def send_signal(self, app):
        #This needs to be send to the ESP32
        # import serial # pyserial is required
        # import time

        # Set the COM port and baud rate according to your ESP32 configuration
        # com_port = 'COM3'  # Change this to your COM port on Windows, e.g., 'COM3'
        # baud_rate = 921600  # Change this to match your ESP32 configuration

        try:
            # Open the serial connection
            self.ser = serial.Serial(self.com_port, self.baud_rate, timeout=1)
            # Flush any existing data in the input buffer
            time.sleep(2)
            self.ser.flushInput()
        except:
            print("Not able to open the connection!")
            app.update_status("Device not available !")
            return

        try:
            # Send the marvCode (displacement history) to ESP32
            print("Sending singal now")
            SendCode2Motor.SendMarvCode2Motor(self.ser, self.shaking_data_instance)
            app.update_status("Data sent")
        except:
            print("Device not available")
            app.update_status("Device not available !")
            return

    def start_motor(self, app):
        try:
            # Start the motor
            print("Starting Motor")
            SendCode2Motor.SendCmd2Motor(self.ser, 'start')
            time.sleep(self.t_out[-1])  # Wait for T seconds
            app.update_status("Shaking finished.")
        except:
            print("Device not available")
            app.update_status("Device not available !")
            return



