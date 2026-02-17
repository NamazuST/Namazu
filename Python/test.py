import serial
import time

com_port = 'COM5'
baud_rate = 921600

ser = serial.Serial(com_port, baud_rate, timeout=1)
time.sleep(1.5) # with a slight delayed time, the ESP32 is initialised properly
ser.flushInput()

def SendCmd2Motor(serial_device, command):
    if isinstance(command, str):
        serial_device.write(command.encode() + b'\n')
        response = serial_device.readline().decode('latin-1').strip()  # Decode bytes to string and remove trailing newline
        print(f"Response from ESP32: {response}")
    else:
        raise Exception('This was not a valid command.')
    
SendCmd2Motor(ser, 'info')
SendCmd2Motor(ser, 'reset')
SendCmd2Motor(ser, 'set spmm 27')
SendCmd2Motor(ser, 'set rate 100')
SendCmd2Motor(ser, 'add -20')
SendCmd2Motor(ser, 'start')

res = ser.readline().decode('latin-1').strip()
print(res)
ser.close()