###################################################################################################################################
# Collection of utilities to send MarvCode to the ESP32
###################################################################################################################################

#Function to send send MarvCode actually to the ESP32 but then through the driver steers the motor
def SendMarvCode2Motor(serial_device, shaking_data):
    #split char into lines and store them in an array
    cmd_array = shaking_data.marvCode.split('\n')

    #remove whitespaces
    cmd_array = [item.strip() for item in cmd_array]

    for k in range(0, len(cmd_array)-1):
        # Send a command to the ESP32
        serial_device.write(cmd_array[k].encode() + b'\n')
        # Read the response from the ESP32
        response = serial_device.readline().decode().strip()  # Decode bytes to string and remove trailing newline
        print(f"Response from ESP32: {response}")
        # Check if the response contains 'OK'
        if 'OK' not in response:
            raise Exception('Response does not contain "OK".')
###################################################################################################################################
#Function to send single commands to the esp -> driver -> motor
def SendCmd2Motor(serial_device, command):
    if isinstance(command, str):
        serial_device.write(command.encode() + b'\n')
        response = serial_device.readline().decode().strip()  # Decode bytes to string and remove trailing newline
        print(f"Response from ESP32: {response}")
    else:
        raise Exception('This was not a valid command.')