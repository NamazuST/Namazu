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
import serial, time

class KanaiTajimiSignal():
    def __init__(self, stepsPerSecond, maxT, maxF, nOmega):
        pass
        # Create an instance of the ShakingData class
        self.shaking_data_instance = ShakingDataClass.ShakingData()

        #Simulation parameters
        self.stepsPerSecond = stepsPerSecond    #Steps performed per second
        self.shaking_data_instance.motorRate = stepsPerSecond
        self.maxT = maxT               #Maximum number of time for the simulation in seconds, 5
        self.maxF = maxF              #Maximum frequency, 12
        self.nOmega = nOmega            #Number of discretized frequencies, 50
        # Kanai-Tajimi scale parameters
        self.w_g = 9 * 2 * np.pi  # Peak frequency
        self.beta_g = 0.6
        # Scale whole PSD function amplitude
        self.S_0 = 0.01

    # Define the PSD function
    def PSD_KT(self, omega):
        numerator = (self.w_g ** 4 + (2 * self.beta_g * self.w_g * omega) ** 2)
        denominator = ((self.w_g ** 2 - omega ** 2) ** 2 + (2 * self.beta_g * self.w_g * omega) ** 2)
        return numerator / denominator * self.S_0

    def update(self):
        # Store the PSD function for later access
        self.shaking_data_instance.psdFunc = self.PSD_KT

        # Define output file name
        self.shaking_data_instance.fileName = f"Shinozuka_Kanai-Tajimi_{self.maxF}_{self.nOmega}_{self.maxT}_{self.stepsPerSecond}"

    def simulate_input_signal(self):
        #Simulate a fixed or mixed harmonic signal
        self.update()
        [pos_out, t_out, self.dt_out, self.shaking_data_instance] = InputSignalMethods.SimulateShinozuka(self.shaking_data_instance, self.maxT, self.maxF*2*np.pi, self.nOmega)
        return pos_out, t_out, self.shaking_data_instance
    
    # # Create a line plot for one frequency
    # plt.plot(t_out, pos_out)
    # # displaying the title
    # plt.title(shaking_data_instance.fileName)
    # plt.xlabel("time in [s]")
    # plt.ylabel("x in [mm]")

    # # Show the plot
    # plt.show()

    def write_marv_code(self):
        #Store the input signal in the shaking data object
        t_out, pos_out, self.shaking_data_instance = self.simulate_input_signal();
        self.shaking_data_instance.inputSignal= [t_out, pos_out]
        #Write the marvCode
        self.shaking_data_instance = WriteMarvCode.WriteMarvCode(self.shaking_data_instance)

    # #This needs to be send to the ESP32
    # import serial # pyserial is required
    # import time

    # # Set the COM port and baud rate according to your ESP32 configuration
    # com_port = 'COM3'  # Change this to your COM port on Windows, e.g., 'COM3'
    # baud_rate = 921600  # Change this to match your ESP32 configuration

    # # Open the serial connection
    # ser = serial.Serial(com_port, baud_rate, timeout=1)
    # # Flush any existing data in the input buffer
    # ser.flushInput()

    # # Send the marvCode (displacement history) to ESP32
    # SendCode2Motor.SendMarvCode2Motor(ser, shaking_data_instance)

    # prompt_response = input("To continue, press 'y': ")
    # if prompt_response.lower() == 'y':
    #     print("Continuing...")
    #     # Start the motor
    #     SendCode2Motor.SendCmd2Motor(ser, 'start')
    #     time.sleep(t_out[-1]+5)  # Wait for T+5 seconds
    # else:
    #     print("Not continuing.")

    # # Close port
    # print("Shaking finished. Closing port...")
    # ser.close()
    # print("Port closed.")


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
