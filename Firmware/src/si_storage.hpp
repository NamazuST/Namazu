#pragma once

#include <stddef.h>
#include <si_math.hpp>
#include <Preferences.h>

namespace si {
    class Storage {
        public:
        bool init();
        size_t load_commands(int*, size_t);
        void write_commands(int*, size_t, size_t);
        config_t load_config();
        void write_config(config_t*);

        private:
#if CONFIG_USE_EEPROM
        Preferences _prefs;
#endif
        bool _valid = false;
    };
}