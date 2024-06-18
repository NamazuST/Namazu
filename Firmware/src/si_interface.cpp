#include <si_interface.hpp>
#include <config.h>

#include <math.h>
#include <limits.h>
#include <stdlib.h>
#include <Arduino.h>

si::Interface::Interface(si::Machine& machine)
 : _machine(machine) {

}

void si::Interface::init() {
    Serial.begin(SERIAL_RATE);
}

void si::Interface::loop() {
    while (Serial.available() > 0) {
        // read the incoming byte:
        _mbyte = Serial.read();
        _buffer[_idx++] = _mbyte;
        if(_mbyte == '\n') {
            switch(parse_cmd(_idx)){
                case 1: Serial.println("ERR: command unknown");
                break;
                case 2: Serial.println("ERR: invalid command format");
                break;
            }
            _idx = 0;
            break;
        }
        if(_idx >= COMMAND_BUFFER_SIZE) {
            Serial.println("ERR: command buffer overflow. Command was too long. Terminate it with \"\\n\" or increase COMMAND_BUFFER_SIZE");
            _idx = 0;
        }
    }
}

si::unsigned_frac_t si::Interface::parse_number(char* str) {
    // returns a unsigned fraction from a string of format 12.3456789
    // ret.factor is -1 and ret.divisor is 0, if the string format is invalid
    size_t i = 0;
    unsigned_frac_t ret = {0,0};
    // hande pre dot
    while ( str[i] >= '0' && str[i] <= '9' ) {
        ++i;
    }
    if (str[i] != '.' && str[i] != '\n' && str[i] != '\0' && str[i] != '\r') {
        //invalid char
        return {-1U,0U};
    }
    char* str_end = &(str[i]);
    ret.factor = strtoul(str,&str_end,10);
    // hande post dot
    if (str[i] == '.' && &(str[i]) != &(_buffer[_idx]) ) {
        ++i;
        unsigned int digits = round(log10(UINT_MAX))-2;
        unsigned int value = pow(10,digits);
        while ( str[i] != '\n' && str[i] != '\r' && str[i] != '\0' && &(str[i]) != &(_buffer[_idx]) ) {
            if (str[i] < '0' || str[i] > '9' ) {
                //invalid char
                return {-1U,0U};
            }
            unsigned int plus = value * (str[i] - '0');
            ret.divisor += plus;
            value /= 10;
            ++i;
        }
        str_end = &(str[i]);
        if (ret.divisor != 0) {
            while (ret.divisor % 10U == 0U) {
                --digits;
                ret.divisor /= 10U;
            }
            unsigned int div = pow(10U,digits+1);
            ret.factor *= pow(10U,digits+1);
            ret.factor += ret.divisor;
            ret.divisor = div;
            
            // Minimize fraction
            unsigned int common_div = gcd(ret.factor, ret.divisor);
            ret.factor /= common_div;
            ret.divisor /= common_div;
        } else {
            ret.divisor = 1;
        }
    } else {
        ret.divisor = 1;
    }
    return ret;
}

si::Interface::error_t si::Interface::set_rate(char* param) {
    if (_machine.is_running()) {
        Serial.println("ERR: machine is busy, cannot change rate");
        return BUSY;
    }
    unsigned_frac_t frac = parse_number(param);
    if (frac.factor == -1 || frac.divisor == 0) {
        return COMMAND_FORMAT;
    }
    if (_machine.set_rate(frac)) {
        Serial.printf("OK: set rate to %.16g hz at a timer interval of %llu\n",
           ((double)frac.factor/(double)frac.divisor),_machine.get_timer_interval());
        return OK;
    }
    Serial.println("ERR: failed to set rate");
    return BUSY;
}

si::Interface::error_t si::Interface::set_spmm(char* param) {
    if (_machine.is_running()) {
        Serial.println("ERR: machine is busy, cannot change spmm");
        return BUSY;
    }
    unsigned_frac_t frac = parse_number(param);
    if (frac.factor == -1 || frac.divisor == 0) {
        return COMMAND_FORMAT;
    }
    _machine.set_spmm(frac);
    Serial.printf("OK: set steps per millimeter to %.16g\n",(double)frac.factor/(double)frac.divisor);
    return OK;
}

si::Interface::error_t si::Interface::cmd_start() {
    if (_machine.is_running()) {
        Serial.println("ERR: machine is already running, cannot start");
        return BUSY;
    }
    if (_machine.get_state() == Machine::state_t::IDLE) {
        Serial.println("ERR: no programm provided, cannot start");
        return NO_PROGRAMM;
    }
    Serial.println("OK: start");
    _machine.start();
    return OK;
}

si::Interface::error_t si::Interface::cmd_stop() {
    if (_machine.get_state() == Machine::state_t::IDLE 
        || _machine.get_state() == Machine::state_t::READY) {
        Serial.println("ERR: machine is not running, cannot stop");
        return BUSY;
    }
    Serial.println("OK: stop");
    _machine.stop();
    return OK;
}

si::Interface::error_t si::Interface::cmd_set(char* param) {
    if (_idx <= 4) return COMMAND_FORMAT;
    if (param[0] == 'r' && param[1] == 'a' && param[2] == 't'
     && param[3] == 'e' && param[4] == ' ') {
        return set_rate(&(param[5]));
    } else if (param[0] == 'm' && param[1] == 'o' && param[2] == 'd'
     && param[3] == 'e' && param[4] == ' ') {
        return COMMAND_UNKNOWN; //TODO
    } else if (param[0] == 's' && param[1] == 'p' && param[2] == 'm'
     && param[3] == 'm' && param[4] == ' ') {
        return set_spmm(&(param[5]));
    }
    return COMMAND_FORMAT;
}

si::Interface::error_t si::Interface::cmd_add(char* param) {
    int sign = 1;
    if (param[0] == '-') {
        sign = -1;
        param++;
    } else if (param[0] == '+') {
        param++;
    }

    unsigned_frac_t num = parse_number(param);
    if (num.factor == -1 || num.divisor == 0) {
        return COMMAND_FORMAT;
    }

    minimize(&num);
    if (num.factor > INT32_MAX) {
        num.factor /= 2;
        num.divisor /= 2;
    }

    frac_t val = {(int)num.factor * sign, num.divisor};
    _machine.add_position(val);
    Serial.println("OK: add");
    return OK;
}

si::Interface::error_t si::Interface::cmd_reset() {
    _machine.reset();
    Serial.printf("OK: reset stored commands\n");
    return OK;
}

si::Interface::error_t si::Interface::cmd_info() {
    String state;
    switch (_machine.get_state()) {
        case Machine::state_t::IDLE: {
            state = "IDLE";
            break;
        }
        case Machine::state_t::READY: {
            state = "READY";
            break;
        }
        case Machine::state_t::PAUSED: {
            state = "PAUSE";
            break;
        }
        case Machine::state_t::RUNNING: {
            state = "RUNNING";
            break;
        }
        case Machine::state_t::MANUAL: {
            state = "MANUAL";
            break;
        }
        case Machine::state_t::PREPARINGDOWN: {
            state = "PREPARINGDOWN";
            break;
        }
        case Machine::state_t::PREPARINGUP: {
            state = "PREPARINGUP";
            break;
        }
        case Machine::state_t::PREPARING: {
            state = "PREPARING";
            break;
        }
        case Machine::state_t::CENTERINGDOWN: {
            state = "CENTERING";
            break;
        }
        case Machine::state_t::CENTERINGUP: {
            state = "CENTERING";
            break;
        }
        case Machine::state_t::FAULT: {
            Machine::fault_t fault = _machine.get_fault();
            state = "FAULT: " + fault;
        }
    }
    String mode;
    switch (_machine.get_mode()) {
        case UNSET: {
            mode = "NO MODE SET";
            break;
        }
        case POSITION: {
            mode = "POSITION";
            break;
        }
        case VELOCITY: {
            mode = "VELOCITY";
            break;
        }
    }
    config_t config = _machine.get_config();
    Machine::status_t status = _machine.get_status();
    Serial.printf( "OK: Info: state: %s, mode %s, command %u of %u, rate: %ghz, spmm: %g, pos: %d\n",
        state.c_str(), mode.c_str(), status.cmd_idx, status.cmd_cnt, (1000000.0/(double) config.timer_interval),
        (double)config.spmm.factor/(double)config.spmm.divisor, status.pos );
    return OK;
}

si::Interface::error_t si::Interface::cmd_center() {
    if (_machine.prepare()) {
        return OK;
    }
    return BUSY;
}

si::Interface::error_t si::Interface::cmd_move_up() {
    if (_machine.move_up()) {
        return OK;
    }
    return BUSY;
}

si::Interface::error_t si::Interface::cmd_move_down() {
    if (_machine.move_down()) {
        return OK;
    }
    return BUSY;
}

int si::Interface::parse_cmd(size_t length) {
    switch(_buffer[0]) {
        case 's': {
            switch (_buffer[1]) {
                case 't': {
                    switch (_buffer[2]) {
                        case 'a': {
                            if (_buffer[3] == 'r' && _buffer[4] == 't') {
                                return cmd_start();
                            }
                        }
                        break;
                        case 'o': {
                            if (_buffer[3] == 'p') {
                                return cmd_stop();
                            }
                        }
                        break;
                    }
                }
                break;
                case 'e': {
                    if (_buffer[2] == 't') {
                        return cmd_set(&(_buffer[4]));
                    }
                }
                break;
            }
        }
        break;
        case 'a': {
            if (_buffer[1] == 'd' && _buffer[2] == 'd' && _buffer[3] == ' ') {
                return cmd_add(&(_buffer[4]));
            }
        }
        break;
        case 'i': {
            if (_buffer[1] == 'n' && _buffer[2] == 'f' && _buffer[3] == 'o') {
                return cmd_info();
            }
        }
        break;
        case 'r': {
            if (_buffer[1] == 'e' && _buffer[2] == 's' && _buffer[3] == 'e' && _buffer[4] == 't') {
                return cmd_reset();
            }
        }
        break;
        case 'c': {
            if (_buffer[1] == 'e' && _buffer[2] == 'n' && _buffer[3] == 't' && _buffer[4] == 'e' && _buffer[5] == 'r') {
                return cmd_center();
            }
        }
        break;
        default: {
            return COMMAND_UNKNOWN;
        }
    }
    return COMMAND_UNKNOWN;
}