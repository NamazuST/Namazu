#include <Arduino.h>
#include "config.h"

#include <si_machine.hpp>
#include <si_interface.hpp>
#include <si_storage.hpp>

si::Storage storage;
si::Machine machine = si::Machine(storage);
si::Interface interface = si::Interface(machine);

#if CONFIG_HAS_BUTTONS
/* START - Button */
IRAM_ATTR void btn_start();
void start(void *) {
    interface.cmd_start();
    attachInterrupt(PIN_BTN_START,btn_start,FALLING);
}
IRAM_ATTR void btn_start() {
    detachInterrupt(PIN_BTN_START);
    xTaskCreate(
        start,              /* Task function. */
        "BtnStart",         /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        0,                  /* Priority of the task. */
        NULL
    );
}

/* STOP - Button */
IRAM_ATTR void btn_stop();
void stop(void *) {
    interface.cmd_stop();
    attachInterrupt(PIN_BTN_STOP,btn_stop,FALLING);
}
IRAM_ATTR void btn_stop() {
    detachInterrupt(PIN_BTN_STOP);
    xTaskCreate(
        stop,               /* Task function. */
        "BtnStop",          /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        0,                  /* Priority of the task. */
        NULL
    );
}

/* PAUSE - Button */
IRAM_ATTR void btn_pause();
void pause(void *) {
    machine.pause();
    attachInterrupt(PIN_BTN_PAUSE,btn_pause,FALLING);
}
IRAM_ATTR void btn_pause() {
    detachInterrupt(PIN_BTN_PAUSE);
    xTaskCreate(
        pause,              /* Task function. */
        "BtnPause",         /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        0,                  /* Priority of the task. */
        NULL
    );
}

/* UP - Button */
IRAM_ATTR void btn_up_rise();
void up_rise(void *) {
    machine.stop();
    attachInterrupt(PIN_BTN_UP,btn_up_rise,FALLING);
}
IRAM_ATTR void btn_up_rise() {
    detachInterrupt(PIN_BTN_UP);
    xTaskCreate(
        up_rise,            /* Task function. */
        "BtnUpRise",        /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        0,                  /* Priority of the task. */
        NULL
    );
}
IRAM_ATTR void btn_up_fall();
void up_fall(void *) {
    machine.move_up();
    attachInterrupt(PIN_BTN_UP,btn_up_rise,RISING);
}
IRAM_ATTR void btn_up_fall() {
    detachInterrupt(PIN_BTN_UP);
    xTaskCreate(
        up_fall,            /* Task function. */
        "BtnUpFall",        /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        0,                  /* Priority of the task. */
        NULL
    );
}

/* DOWN - Button */
IRAM_ATTR void btn_down_rise();
void down_rise(void *) {
    machine.stop();
    attachInterrupt(PIN_BTN_DOWN,btn_down_rise,FALLING);
}
IRAM_ATTR void btn_down_rise() {
    detachInterrupt(PIN_BTN_DOWN);
    xTaskCreate(
        down_rise,          /* Task function. */
        "BtnUpRise",        /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        0,                  /* Priority of the task. */
        NULL
    );
}
IRAM_ATTR void btn_down_fall();
void down_fall(void *) {
    machine.move_down();
    attachInterrupt(PIN_BTN_DOWN,btn_down_rise,RISING);
}
IRAM_ATTR void btn_down_fall() {
    detachInterrupt(PIN_BTN_DOWN);
    xTaskCreate(
        down_fall,            /* Task function. */
        "BtnUpFall",        /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        0,                  /* Priority of the task. */
        NULL
    );
}
#endif

#if CONFIG_HAS_LIMITS
/* Limit Switch MIN */
IRAM_ATTR void limit_min();
void min(void *) {
    machine.limit_min();
    attachInterrupt(PIN_LIMIT_MIN,limit_min,FALLING);
}
IRAM_ATTR void limit_min() {
    detachInterrupt(PIN_LIMIT_MIN);
    xTaskCreate(
        min,              /* Task function. */
        "LimitMin",         /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        0,                  /* Priority of the task. */
        NULL
    );
}

/* Limit Switch MAX */
IRAM_ATTR void limit_max();
void max(void *) {
    machine.limit_max();
    attachInterrupt(PIN_LIMIT_MAX,limit_max,FALLING);
}
IRAM_ATTR void limit_max() {
    detachInterrupt(PIN_LIMIT_MAX);
    xTaskCreate(
        max,                /* Task function. */
        "LimitMax",         /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        0,                  /* Priority of the task. */
        NULL
    );
}
#endif

/* MAIN */
void setup() {
    interface.init();
    machine.init();
    if (!storage.init()) {
        Serial.println("FAILED TO INITALIZE STORAGE");
    }
#if CONFIG_HAS_LIMITS
    attachInterrupt(PIN_LIMIT_MIN,limit_min,FALLING);
    attachInterrupt(PIN_LIMIT_MAX,limit_max,FALLING);
#endif
#if CONFIG_HAS_BUTTONS
    attachInterrupt(PIN_BTN_START,btn_start,FALLING);
    attachInterrupt(PIN_BTN_STOP,btn_stop,FALLING);
    attachInterrupt(PIN_BTN_PAUSE,btn_pause,FALLING);
    attachInterrupt(PIN_BTN_UP,btn_up_fall,FALLING);
    attachInterrupt(PIN_BTN_DOWN,btn_down_fall,FALLING);
#endif

}

void loop() {
    interface.loop();
}