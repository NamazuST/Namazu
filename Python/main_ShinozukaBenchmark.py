###################################################################################################################################
#Main script to simulate and send the Shonzuka Benchmark signal to the ESP32 -> Driver -> Motor
#Import shaking data object
from Classes import ShakingDataClass
#Import Namazu framework functions
from Methods import InputSignalMethods
from Functions import WriteMarvCode
from Functions import SendCode2Motor
#Import utilities
import matplotlib.pyplot as plt
import serial, time

class ShnozukaBenchmark():

    def __init__(self, amplitude_scaling=3):
        # Create an instance of the ShakingData class
        self.shaking_data_instance = ShakingDataClass.ShakingData()

        #Simulation parameters
        self.Shinozuka_amplitude_scaling = amplitude_scaling; #Parameter to scale the amplitude of the shinozuka benchmark signals

    def simulate_input_signal(self):
        #Simulate a fixed or mixed harmonic signal
        [pos_out, t_out, dt_out, maxT_out, self.shaking_data_instance] = InputSignalMethods.SimulateShinozukaBenchmark(self.Shinozuka_amplitude_scaling, self.shaking_data_instance)
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
        self.pos_out, self.t_out, self.shaking_data_instance = self.simulate_input_signal()
        #Store the input signal in the shaking data object
        self.shaking_data_instance.inputSignal= [self.t_out, self.pos_out]

        #Write the marvCode
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