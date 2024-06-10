#pragma once

#include <stdint.h>

namespace si {
    typedef struct {
        unsigned int factor;
        unsigned int divisor;
    } unsigned_frac_t;

    typedef struct {
        int factor;
        unsigned int divisor;
    } frac_t;

    typedef enum {
        UNSET,
        POSITION,
        VELOCITY
    } mode_t;

    typedef struct {
        uint64_t timer_interval = 0;
        mode_t mode = mode_t::UNSET;
        unsigned_frac_t spmm = {0,0};
        unsigned_frac_t rate = {0,0};
    } config_t;

    int mulFrac2Int(frac_t, unsigned_frac_t);
    unsigned int mulFrac2Int(unsigned_frac_t, unsigned_frac_t);
    unsigned int gcd(unsigned int, unsigned int);
    void minimize(frac_t*);
    void minimize(unsigned_frac_t*);
}