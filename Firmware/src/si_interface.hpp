#pragma once

#include <stddef.h>
#include <si_math.hpp>
#include <si_machine.hpp>

#define COMMAND_BUFFER_SIZE 256

namespace si {
    class Interface {
        public:

        typedef enum {
            OK,
            COMMAND_UNKNOWN,
            COMMAND_FORMAT,
            BUSY,
            NO_PROGRAMM
        } error_t;

        Interface(Machine&);

        void init();
        void loop();
        int parse_cmd(size_t);
        error_t cmd_start();
        error_t cmd_pause();
        error_t cmd_stop();
        error_t cmd_set(char*);
        error_t cmd_add(char*);
        error_t cmd_reset();
        error_t cmd_info();
        error_t cmd_center();
        error_t cmd_move_up();
        error_t cmd_move_down();

        private:
        error_t set_rate(char*);
        error_t set_spmm(char*);
        unsigned_frac_t parse_number(char*);

        char _buffer[COMMAND_BUFFER_SIZE];
        size_t _idx = 0;
        char _mbyte;
        Machine& _machine;
    };
}