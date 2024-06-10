#include <si_storage.hpp>
#include <string.h>
#include <si_math.hpp>
#include <config.h>

#define READ 1
#define WRITE 0

bool si::Storage::init() {
#if CONFIG_USE_EEPROM
    bool result = _prefs.begin("si", READ);
    _prefs.end();
    return result;
#else
    return true;
#endif
}

size_t si::Storage::load_commands(int* queue, size_t idx) {
#if CONFIG_USE_EEPROM
    if (_prefs.begin("si", READ)) {
        size_t cnt = _prefs.getUInt("cmd_cnt");
        size_t segment = idx / (COMMAND_QUEUE_SIZE / 2);
        if (cnt > 0 && idx < cnt) {
            _prefs.getBytes(String(segment).c_str(), queue, (COMMAND_QUEUE_SIZE / 2));
        }
        _prefs.end();
        return cnt;
    }
#endif
    return 0;
}

void si::Storage::write_commands(int* queue, size_t idx, size_t cnt) {
#if CONFIG_USE_EEPROM   
    if(_prefs.begin("si", WRITE)) {
        size_t segment = idx / (COMMAND_QUEUE_SIZE / 2);
        if (cnt > 0 && idx < cnt) {
            _prefs.putUInt("cmd_cnt", cnt);
            _prefs.putBytes(String(segment).c_str(),queue,(COMMAND_QUEUE_SIZE / 2));
        }
        _prefs.end();
    }
#endif
}

si::config_t si::Storage::load_config() {
    config_t config;
#if CONFIG_USE_EEPROM
    if (_prefs.begin("si", READ)) {
        if (_prefs.getBytes("config", &config, sizeof(config_t)) == sizeof(config_t)) {
            _prefs.end();
            return config;
        }
    }
#endif
    config_t default_config;
    return default_config;
}

void si::Storage::write_config(config_t* config) {
#if CONFIG_USE_EEPROM
    if (_prefs.begin("si", WRITE)) {
        _prefs.putBytes("config", config, sizeof(config_t));
        _prefs.end();
    }
#endif
}