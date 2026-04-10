import os
import serial
import numpy as np
from tqdm import tqdm

class NamazuInstance:
    def __init__(self, comport = "missing"):
        self.motorStartupDelay : float = 5.0 
        self.motionStartupDelay : float = 5.0
        self.motorRate : float = 100.0
        self.steps_per_mm : float = 27.0
        self.comport : str = comport
        self.baudrate : int = 921600
        self.serial_object = None

        try:
            self.load_config("config/config.json")
        except Exception as e:
            print(f"Error loading config: {e}")
            print("Using default parameters and creating config file.")
            self.save_config("config/config.json")

    def send_command(self, command):
        #split char into lines and store them in an array
        cmd_array = command.split('\n')

        #remove whitespaces
        cmd_array = [item.strip() for item in cmd_array]

        n_cmd = len(cmd_array)

        response = ""

        for k in tqdm(range(0, n_cmd-1), desc="Sending commands"):
            # Send a command to the ESP32
            self.serial_object.write(cmd_array[k].encode() + b'\n')
            # Read the response from the ESP32
            response = self.serial_object.readline().decode().strip()  # Decode bytes to string and remove trailing newline
            # print(f"Response from ESP32: {response}")
            # Check if the response contains 'OK'
            if not response.startswith("OK"):
                raise Exception('Response does not contain "OK".')
            
        return response

    def connect(self):
        # Open the serial connection
        print(f"Opening serial port {self.comport} at baud rate {self.baudrate}...")
        ser = serial.Serial(self.comport, self.baudrate, timeout=1)
        # Flush any existing data in the input buffer
        print("Flushing input buffer...")
        ser.flushInput()
        self.serial_object = ser

        if not self.check_serial():
            print("Error: ESP32 did not respond correctly. Check the connection and try again.")
            self.disconnect()
            raise ConnectionError("Failed to connect to ESP32.")
        
    def disconnect(self):
        if self.serial_object and self.serial_object.is_open:
            print(f"Closing serial port {self.comport}...")
            try:
                self.serial_object.close()
            except Exception as e:
                print(f"Couldn't close port {self.comport}: {e}")
            self.serial_object = None

    def check_serial(self):
        self.serial_object.write('info'.encode() + b'\n')
        # Read the response from the ESP32
        response = self.serial_object.readline().decode().strip()  # Decode bytes to string and remove trailing newline
        return response.startswith("OK")

    def load_config(self, config_path):
        import json
        with open(config_path, 'r') as f:
            config = json.load(f)
            self.motorStartupDelay = config.get("motorStartupDelay", self.motorStartupDelay)
            self.motionStartupDelay = config.get("motionStartupDelay", self.motionStartupDelay)
            self.motorRate = config.get("motorRate", self.motorRate)
            self.steps_per_mm = config.get("steps_per_mm", self.steps_per_mm)
            self.baudrate = config.get("baudrate", self.baudrate)

    def save_config(self, config_path):
        import json
        config = {
            "motorStartupDelay": self.motorStartupDelay,
            "motionStartupDelay": self.motionStartupDelay,
            "motorRate": self.motorRate,
            "steps_per_mm": self.steps_per_mm,
            "baudrate": self.baudrate
        }
        with open(config_path, 'w') as f:
            json.dump(config, f, indent=4)

    def query_status(self):
        """
        Query device status without validation.
        Returns the raw status response from the device.
        Useful for monitoring loops that need actual status info, not just "OK".
        """
        if not self.serial_object or not self.serial_object.is_open:
            raise ConnectionError("Serial port is not open")
        
        self.serial_object.write(b'info\n')
        response = self.serial_object.readline().decode().strip()
        return response