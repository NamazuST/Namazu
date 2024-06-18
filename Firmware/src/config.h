#define DEBUG true

#define SERIAL_RATE 921600
#define COMMAND_BUFFER_SIZE 256
#define COMMAND_QUEUE_SIZE 24576

#define DEFAULT_RATE 10 //hz
#define DEFAULT_SPMM 30 //steps/Millimeter
#define MOVEMENT_SPEED 50 // Millimeter/Second
#define TIMER_ID 2
#define TIMER_PRESCALER 80
#define PWM_DUTYCYCLE 128
#define FREQUENCY_MIN 1.0

#define CONFIG_HAS_BUTTONS false
#define CONFIG_HAS_LIMITS false
#define CONFIG_HAS_DRIVER_DIAG false
#define CONFIG_USE_EEPROM false
#define CONFIG_FLASH_SIZE 4194304 // byte

#define PIN_EN 5
#define PIN_INVERT_EN 0
#define PIN_DIR 13
#define PIN_INVERT_DIR 0
#define PIN_STEP 2
#define PIN_CHANNEL 0
#define PIN_CHANNEL_RES 8
#define PIN_DIAG -1

#define PIN_BTN_START 22
#define PIN_BTN_STOP 18
#define PIN_BTN_PAUSE 15
#define PIN_BTN_UP 19
#define PIN_BTN_DOWN 21
#define PIN_BTN_CENTER 4
#define PIN_LIMIT_MIN 14
#define PIN_LIMIT_MAX 27

#define PIN_TEST_FREQ 10000 //hz