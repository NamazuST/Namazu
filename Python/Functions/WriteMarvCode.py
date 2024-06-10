###################################################################################################################################
# Function to convert the position signal into MarvCode and store it in a text file
###################################################################################################################################
import os
from datetime import datetime

def WriteMarvCode(shaking_data):
    # Compiling marv code from positions and saving to the shakingData format

    multiplier = 32  # factor for converting from 1600 spmm to other value!
    steps_per_mm = 27  # specific for the motor, CHANGE IF TABLE OR MICROSTEPPING IS CHANGED
    # 40 because: 20 teeth for a 2mm-tooth belt and gear, 1600 spmm
    # 5 because: 20 teeth for a 2mm tooth belt and gear,
    # on NEMA 23 (1.8° per step)

    form = 'add %5.4f\n'

    file_header = f'reset\nset spmm {steps_per_mm}\nset rate {shaking_data.motorRate}\n'
    cmd = file_header
    pos = shaking_data.inputSignal[1]

    for i in range(len(pos)):
        cmd += form % pos[i]

    shaking_data.marvCode = cmd

    try:
        current_directory = os.getcwd()
        print("Current directory:", current_directory)
        # Get current timestamp
        timestamp = datetime.now()
        # Convert timestamp to string
        timestamp_str = timestamp.strftime("%Y%m%d_%H%M%S")
        filename = timestamp_str+'_'+shaking_data.fileName+'.txt'
        marvcodefolder = 'MarvCode'
        fullfilelocation = os.path.join(current_directory, marvcodefolder ,filename)
        with open(fullfilelocation, 'w') as file:
            file.write(shaking_data.marvCode + '\n')
        print(f"Marv code has been successfully written to {filename}")
    except Exception as e:
        print(f"An error occurred: {str(e)}")

    return shaking_data