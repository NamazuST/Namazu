import numpy as np
###################################################################################################################################
# Class definition for the shaking data object
###################################################################################################################################
class ShakingData:
    def __init__(self):
        self.dataPlate = None  # data measured from the table itself
        self.dataObject = None  # data measured from the object (so far only one object is supported)
        self.transformedDataPlate = np.array([])  # double
        self.transformedDataObject = np.array([])  # double
        self.anglesSensorPlate = np.zeros((3, 1), dtype=float)
        self.anglesSensorObject = np.zeros((3, 1), dtype=float)
        self.accelerationSensorsActive = False  # logical
        self.numberOfAccSensors = 0.0  # double
        self.motorStartupDelay = 0.0  # double
        self.motionStartupDelay = 0.0  # double
        self.sampleRate = 0.0  # double
        self.motorRate = 0.0  # double
        self.inputSignal = np.array([])  # double
        self.inputVelocity = np.array([])  # double
        self.inputAcceleration = np.array([])  # double
        self.marvCode = ""  # string
        self.signalFiltered = False  # logical
        self.simulationType = None  # TODO: Define enumeration for simulation type
        self.fileName = ""  # string
        self.signalGenerator = None  # TODO: Define enumeration for signal generator method
        self.psdFunc = None  # function handle
###################################################################################################################################
    def setup(self):
        # Numerical differentiation to obtain speed and velocity values from the position signal
        # adds a 0 as an initial value for the first time step
        self.inputVelocity = np.column_stack([
            self.inputSignal[:, 0],
            np.hstack([0, np.diff(self.inputSignal[:, 1]) / np.diff(self.inputSignal[:, 0])])
        ])

        self.inputAcceleration = np.column_stack([
            self.inputSignal[:, 0],
            np.hstack([0, np.diff(self.inputVelocity[:, 1]) / np.diff(self.inputSignal[:, 0])])
        ])