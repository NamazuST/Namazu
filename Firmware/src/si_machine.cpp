#include <si_machine.hpp>
#include <Arduino.h>
#include <config.h>
#include <nvs_flash.h>

si::Machine* si::Machine::_instance;

si::Machine::Machine(Storage& storage)
 : _storage(storage) {
    _instance = this;
}

void si::Machine::init() {
    _config = _storage.load_config();
    if (_config.timer_interval == 0) {
        _config.timer_interval = (1000000UL / DEFAULT_RATE);
    }
    if (_config.rate.divisor == 0) {
        _config.rate = {DEFAULT_RATE,1};
    }
    if (_config.spmm.divisor == 0) {
        _config.spmm = {DEFAULT_SPMM,1};
    }
    if (_config.mode == UNSET) {
        _config.mode = POSITION;
    }

    _status.cmd_cnt = _storage.load_commands(_cur_cmd_queue, 0);
    if (_status.cmd_cnt > (COMMAND_QUEUE_SIZE / 2)) {
        _storage.load_commands(_spare_cmd_queue, (COMMAND_QUEUE_SIZE / 2));
    }
    if (_status.cmd_cnt > 0) {
        _state = READY;
    }

    _queue = xQueueCreate( 10, sizeof( int ) );
    _queue_flip = xQueueCreate( 2, sizeof( int* ) );

    _cmd_timer = timerBegin(TIMER_ID, TIMER_PRESCALER, true);
    timerAlarmWrite(_cmd_timer, _config.timer_interval, true);
    timerAttachInterrupt(_cmd_timer, call_next_cmd, true);

    xTaskCreate(
        call_set_frequence, /* Task function. */
        "SetFrequence",     /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        0,                  /* Priority of the task. */
        NULL
    );
    xTaskCreate(
        call_fill_queue,    /* Task function. */
        "FillQueue",        /* String with name of task. */
        4096,               /* Stack size in bytes. */
        NULL,               /* Parameter passed as input of the task */
        1,                  /* Priority of the task. */
        NULL
    );
    
}

void si::Machine::start() {
    switch (_state){
    case READY:
        //timerAttachInterrupt(_cmd_timer, call_next_cmd, true);  -- conflicts with esp32-wroom-32 (no wroom32d)
        timerAlarmEnable(_cmd_timer);
        _status.cmd_idx = 0;
        _status.pos = 0;
        if (_new_cmd) {
            _storage.write_commands(_cmd_queue_0, 0, _status.cmd_cnt);
            if (_status.cmd_cnt > (COMMAND_QUEUE_SIZE / 2)) {
                _storage.write_commands(_cmd_queue_1, (COMMAND_QUEUE_SIZE / 2), _status.cmd_cnt);
            }
            if (_cmd_queue_buf != nullptr) {
                _storage.write_commands(_cmd_queue_1, (_cmd_segment * (COMMAND_QUEUE_SIZE / 2)), _status.cmd_cnt);
            }
            _new_cmd = false;
        }
    case PAUSED:
        _state = RUNNING;
        timerAlarmEnable(_cmd_timer);
        timerStart(_cmd_timer);
        digitalWrite(PIN_EN, HIGH != PIN_INVERT_EN);
    default:
        return;
    }
}

void si::Machine::stop() {
#if DEBUG
    Serial.println("DEBUG: triggerd stop");
#endif
    timerAlarmDisable(_cmd_timer);
    size_t cmd_idx = 0;
    xQueueSend(_queue, &cmd_idx, portMAX_DELAY);
    if (_state == RUNNING || _state == MANUAL) {
        set_resting_state();
    }
}

void si::Machine::pause() {
#if DEBUG
    Serial.println("DEBUG: triggerd pause");
#endif
    if (_state == RUNNING) {
        timerAlarmDisable(_cmd_timer);
        size_t cmd_idx = 0;
        _state = PAUSED;
        xQueueSend(_queue, &cmd_idx, portMAX_DELAY);
    }
}

bool si::Machine::is_running() {
    return (_state == RUNNING);
}

bool si::Machine::set_rate(unsigned_frac_t rate) {
    if (_state == IDLE || _state == READY) {
        uint64_t factor = 1000000UL * (uint64_t)rate.divisor;
        _config.timer_interval = factor / (uint64_t)rate.factor;
        _config.rate = rate;
        timerAlarmWrite(_cmd_timer, _config.timer_interval, true);
        _storage.write_config(&_config);
        return true;
    }
    return false;
}

bool si::Machine::set_spmm(unsigned_frac_t spmm) {
    _config.spmm = spmm;
    _storage.write_config(&_config);
    return true;
}

si::Machine::state_t si::Machine::get_state() {
    return _state;
}

si::mode_t si::Machine::get_mode() {
    return _config.mode;
}

uint64_t si::Machine::get_timer_interval() {
    return _config.timer_interval;
}

si::Machine::fault_t si::Machine::get_fault() {
    return _fault;
}

si::config_t si::Machine::get_config() {
    return _config;
}

si::Machine::status_t si::Machine::get_status() {
    return _status;
}

bool si::Machine::add_position(frac_t pos) {
    if (_state == IDLE) {
        _state = READY;
    }
    if (_status.cmd_cnt < (COMMAND_QUEUE_SIZE / 2)) {
        _cmd_queue_0[_status.cmd_cnt++] = mulFrac2Int(pos, _config.spmm);
#if DEBUG
        Serial.println("DEBUG: cmd stored into cur_q");
#endif
    } else if (_status.cmd_cnt < COMMAND_QUEUE_SIZE) {
        _cmd_queue_1[(_status.cmd_cnt++) - (COMMAND_QUEUE_SIZE / 2)] = mulFrac2Int(pos, _config.spmm);
#if DEBUG
        Serial.println("DEBUG: cmd stored into spare_q");
#endif
    } else {
        size_t segment = _status.cmd_cnt / (COMMAND_QUEUE_SIZE / 2);
        if (segment != _cmd_segment) {
#if DEBUG
            Serial.println("DEBUG: new cmd segment");
#endif
            if (_cmd_queue_buf != nullptr) {
#if DEBUG
                Serial.println("DEBUG: found spare_q, write and free mem");
#endif
                _storage.write_commands(_cmd_queue_buf, (_cmd_segment * (COMMAND_QUEUE_SIZE / 2)), (_status.cmd_cnt + 1));
                free(_cmd_queue_buf);
            }
            _cmd_queue_buf = (int*) malloc((COMMAND_QUEUE_SIZE / 2) * sizeof(int));
            if (_cmd_queue_buf == nullptr) {
                Serial.println("ERR: failed to allocate memory for commands");
                return false;
            }
#if DEBUG
            Serial.println("DEBUG: got dynamic memory for command_q");
#endif
            _cmd_queue_buf[(_status.cmd_cnt++) - (segment * (COMMAND_QUEUE_SIZE / 2))] = mulFrac2Int(pos, _config.spmm);
            _cmd_segment = segment;
        } else {
#if DEBUG
            Serial.println("DEBUG: stored cmd into dynamic memory");
#endif
            _cmd_queue_buf[(_status.cmd_cnt++) - (segment * (COMMAND_QUEUE_SIZE / 2))] = mulFrac2Int(pos, _config.spmm);
        }
    }
    _new_cmd = true;
    return true;
}

bool si::Machine::reset() {
#if CONFIG_USE_EEPROM
    nvs_flash_erase(); // erase the NVS partition and...
    nvs_flash_init();
    _storage.write_config(&_config);
#endif
    if (_state == READY) {
        _status.cmd_cnt = 0;
        _status.cmd_idx = 0;
        _status.pos = 0;
        _state = IDLE;
        return true;
    } else if (_state == FAULT) {
        ESP.restart();
    }
    return false;
}

bool si::Machine::move_up() {
#if DEBUG
    Serial.println("DEBUG: triggerd move up");
#endif
    if (_state != READY && _state != IDLE) return false;
    _state = MANUAL;
    _frequency = (MOVEMENT_SPEED * (double)_config.spmm.factor) / (double)_config.spmm.divisor;
    digitalWrite(PIN_DIR, HIGH != PIN_INVERT_DIR);
    size_t cmd_idx = 0;
    xQueueSend(_queue, &cmd_idx, portMAX_DELAY);
    return true;
}

bool si::Machine::move_down() {
#if DEBUG
    Serial.println("DEBUG: triggerd move down");
#endif
    if (_state != READY && _state != IDLE) return false;
    _state = MANUAL;
    _frequency = (MOVEMENT_SPEED * (double)_config.spmm.factor) / (double)_config.spmm.divisor;
    digitalWrite(PIN_DIR, LOW != PIN_INVERT_DIR);
    size_t cmd_idx = 0;
    xQueueSend(_queue, &cmd_idx, portMAX_DELAY);
    return true;
}

void si::Machine::move_stop() {
#if DEBUG
    Serial.println("DEBUG: triggerd move stop");
#endif
    if (_state != MANUAL) return;
    timerAlarmDisable(_cmd_timer);
    size_t cmd_idx = 0;
    xQueueSend(_queue, &cmd_idx, portMAX_DELAY);
    set_resting_state();
}


void si::Machine::set_frequence() {
    // TODO: queue-flip, load commands at flip
    pinMode(PIN_DIR,OUTPUT);
    digitalWrite(PIN_DIR,LOW != PIN_INVERT_DIR);
    pinMode(PIN_EN,OUTPUT);
    digitalWrite(PIN_EN,LOW != PIN_INVERT_EN);

    size_t cmd_idx = 0;
    ledcAttachPin(PIN_STEP, PIN_CHANNEL);

    while (true) {
        xQueueReceive(_queue, &cmd_idx, portMAX_DELAY);
        switch (_state) {
            case RUNNING: {
                // cmd_queue size is limited in IRAM
                // therefore, use multible queues and use the first
                //  while the other is refilled with commands by a task
                _frequency = (double)(_cur_cmd_queue[cmd_idx] - _status.pos) * (1000000.0 / (double)_config.timer_interval);
                _status.pos = _cur_cmd_queue[cmd_idx];
                if (_frequency < -FREQUENCY_MIN) {
                    _frequency *= -FREQUENCY_MIN;
                    digitalWrite(PIN_DIR, LOW != PIN_INVERT_DIR);
                } else if (_frequency < FREQUENCY_MIN) {
                    _frequency = 0.0;
                } else {
                    digitalWrite(PIN_DIR, HIGH != PIN_INVERT_DIR);
                }
                break;
            }
            case PREPARING:
            case PREPARINGDOWN:
            case PREPARINGUP:
            case CENTERINGDOWN:
            case CENTERINGUP:
            case MANUAL: {
                if (_frequency < FREQUENCY_MIN) {
                    _frequency = 0.0;
                    digitalWrite(PIN_EN, LOW != PIN_INVERT_EN);
                } else {
                    digitalWrite(PIN_EN, HIGH != PIN_INVERT_EN);
                }
                break;
            }
            default: {
                _frequency = 0.0;
                digitalWrite(PIN_EN, LOW != PIN_INVERT_EN);
                break;
            }
        }
#if DEBUG
        Serial.printf("DEBUG: %d : %f - %llu\n",_cur_cmd_queue[cmd_idx], _frequency, _config.timer_interval);
#endif
        ledcWriteTone(PIN_CHANNEL, _frequency);
    }
    vTaskDelete( NULL );
}

bool si::Machine::prepare() {
    /*
        Drives carriage into upper and lower limit-switch.
        - finds middle position
        - triggers limit_min
     */
#if DEBUG
    Serial.println("DEBUG: triggerd center routine");
#endif
#if CONFIG_HAS_LIMITS
    if (_state != READY && _state != IDLE) {
        return false;
    }
    _state = PREPARING;
    _frequency = (MOVEMENT_SPEED * (double)_config.spmm.factor) / (double)_config.spmm.divisor;
    digitalWrite(PIN_DIR, LOW != PIN_INVERT_DIR);
    size_t cmd_idx = 0;
    xQueueSend(_queue, &cmd_idx, portMAX_DELAY);
    return true;
#else
    return false;
#endif
}

void si::Machine::limit_min() {
#if DEBUG
    Serial.println("DEBUG: triggerd limit min");
#endif
#if CONFIG_HAS_LIMITS
    switch (_state) {
        case PREPARING: {
            _state = PREPARINGUP;
            digitalWrite(PIN_DIR, HIGH != PIN_INVERT_DIR);
            _ts_low = micros();
            break;
        }
        case PREPARINGUP: {
#endif
#if DEBUG & CONFIG_HAS_LIMITS
            Serial.println("DEBUG: protected debounce of limit min");
#endif
#if CONFIG_HAS_LIMITS
            break;
        }
        case PREPARINGDOWN: {
            _state = CENTERINGUP;
            _ts_high = micros();
            digitalWrite(PIN_DIR, LOW != PIN_INVERT_DIR);
            _delay_timer = timerBegin(0, 80, true);
            uint64_t delta_time = ((uint64_t)_ts_high - (uint64_t)_ts_low) / 2;
            // drive downwards half of the time it took to reach limit_max
            // should be almost the center
            timerAttachInterrupt(_delay_timer, &call_centered, true);
            timerAlarmWrite(_delay_timer, delta_time, false);
            timerAlarmEnable(_delay_timer);
            break;
        }
        case CENTERINGUP: {
#endif
#if DEBUG & CONFIG_HAS_LIMITS
            Serial.println("DEBUG: protected debounce of limit min");
#endif
#if CONFIG_HAS_LIMITS
            break;
        }
        default: {
            _state = FAULT;
            stop();
            Serial.println("ERR: triggered lower limit switch - stopped");
        }
    }
#endif
}

void si::Machine::limit_max() {
#if DEBUG
    Serial.println("DEBUG: triggerd limit max");
#endif
#if CONFIG_HAS_LIMITS
    switch (_state) {
        case PREPARINGUP: {
            _state = CENTERINGDOWN;
            _ts_high = micros();
            digitalWrite(PIN_DIR, LOW != PIN_INVERT_DIR);
            _delay_timer = timerBegin(0, 80, true);
            uint64_t delta_time = ((uint64_t)_ts_high - (uint64_t)_ts_low) / 2;
            // drive downwards half of the time it took to reach limit_max
            // should be almost the center
            timerAttachInterrupt(_delay_timer, &call_centered, true);
            timerAlarmWrite(_delay_timer, delta_time, false);
            timerAlarmEnable(_delay_timer);
            break;
        }
        case CENTERINGDOWN: {
#endif
#if DEBUG & CONFIG_HAS_LIMITS
            Serial.println("DEBUG: protected debounce of limit max");
#endif
#if CONFIG_HAS_LIMITS
            break;
        }
        case PREPARING: {
            _state = PREPARINGDOWN;
            digitalWrite(PIN_DIR, HIGH != PIN_INVERT_DIR);
            _ts_low = micros();
            break;
        }
        case PREPARINGDOWN: {
#endif
#if DEBUG & CONFIG_HAS_LIMITS
            Serial.println("DEBUG: protected debounce of limit max");
#endif
#if CONFIG_HAS_LIMITS
            break;
        }
        default: {
            _state = FAULT;
            stop();
            Serial.println("ERR: triggered upper limit switch - stopped");
        }
    }
#endif
}

void si::Machine::call_set_frequence(void *) {
    _instance->set_frequence();
}

void si::Machine::fill_queue() {
    int cmd_idx;
    while (true) {
        xQueueReceive(_queue_flip, &cmd_idx, portMAX_DELAY);
        _storage.load_commands(_spare_cmd_queue, cmd_idx);
    }
}

void si::Machine::call_fill_queue(void *) {
    _instance->fill_queue();
}

void IRAM_ATTR si::Machine::next_cmd() {
    size_t cmd_idx = _status.cmd_idx % (COMMAND_QUEUE_SIZE / 2);
    //queueflip
    if (cmd_idx == 0 && _status.cmd_idx != 0) {
        int* tmp = _cur_cmd_queue;
        _cur_cmd_queue = _spare_cmd_queue;
        _spare_cmd_queue = tmp;
        //size_t spare_cmd_idx = _status.cmd_idx + (COMMAND_QUEUE_SIZE / 2);
    }
    if (_status.cmd_idx < _status.cmd_cnt) {
        ++_status.cmd_idx;
    } else {
        cmd_idx = 0;
        _state = READY;
        timerAlarmDisable(_cmd_timer);
        //timerDetachInterrupt(_cmd_timer); -- conflicts with esp32-wroom-32 (no wroom32d)
    }
    xQueueSend(_queue, &cmd_idx, portMAX_DELAY);
}

void si::Machine::centered() {
#if DEBUG & CONFIG_HAS_LIMITS
    Serial.println("DEBUG: centering finished");
#endif
    set_resting_state();
    stop();
    timerAlarmDisable(_delay_timer);
    //timerEnd(_delay_timer);
    timerDetachInterrupt(_delay_timer);
}

void IRAM_ATTR si::Machine::call_next_cmd() {
    _instance->next_cmd();
}

void IRAM_ATTR si::Machine::call_centered() {
    _instance->centered();
}

void si::Machine::set_resting_state() {
    if (_status.cmd_cnt > 0)
        _state = READY;
    else 
        _state = IDLE;
}