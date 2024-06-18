#pragma once


#include <config.h>
#include <si_math.hpp>
#include <stddef.h>
#include <Arduino.h>
#include <si_storage.hpp>

namespace si {
    class Machine {
        public:
        
        typedef enum {
            IDLE,
            READY,
            RUNNING,
            PAUSED,
            MANUAL,
            PREPARINGDOWN,
            PREPARINGUP,
            PREPARING,
            CENTERINGUP,
            CENTERINGDOWN,
            FAULT
        } state_t;

        typedef enum {
            NONE,
            ENDSTOP_TRIGGERED,
            LOST_STEPS,
            POSITION_OFF_BOUNDS
        } fault_t;

        typedef struct {
            size_t cmd_idx = 0;
            size_t cmd_cnt = 0;
            int pos = 0;
        } status_t;

        Machine(Storage&);

        void start();
        void stop();
        void pause();
        bool is_running();
        bool set_rate(si::unsigned_frac_t);
        bool set_spmm(unsigned_frac_t);
        state_t get_state();
        mode_t get_mode();
        uint64_t get_timer_interval();
        fault_t get_fault();
        config_t get_config();
        status_t get_status();
        bool add_position(frac_t);
        bool reset();
        bool move_up();
        bool move_down();
        void move_stop();
        bool prepare();

        void init();
        void set_frequence();
        void fill_queue();
        void next_cmd();
        void centered();
        
        void limit_min();
        void limit_max();

        static void call_set_frequence(void *);
        static void call_fill_queue(void *);
        static void call_next_cmd();
        static void call_centered();

        private:
        static Machine* _instance;

        Storage& _storage;
        config_t _config;

        hw_timer_t* _cmd_timer = NULL;
        hw_timer_t* _delay_timer = NULL;
        QueueHandle_t _queue;
        QueueHandle_t _queue_flip;
        int _cmd_queue_0[COMMAND_QUEUE_SIZE / 2];
        int _cmd_queue_1[COMMAND_QUEUE_SIZE / 2];
        int* _cur_cmd_queue = _cmd_queue_0;
        int* _spare_cmd_queue = _cmd_queue_1;

        state_t _state = IDLE;
        fault_t _fault = fault_t::NONE;
        status_t _status;
        bool _new_cmd = false;
        size_t _cmd_segment = 0;
        int* _cmd_queue_buf = nullptr;

        double _frequency = 0.0;
        unsigned long _ts_low = 0;
        unsigned long _ts_high = 0;

        void set_resting_state();
    };
}