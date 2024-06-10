#include <si_math.hpp>

namespace si {
    int mulFrac2Int(frac_t a, unsigned_frac_t b) {
        int64_t factor = (int64_t)a.factor * (int64_t)b.factor;
        int64_t divisor = (int64_t)a.divisor * (int64_t)b.divisor;
        factor /= divisor;
        if (factor < INT32_MIN) return INT32_MIN;
        if (factor > INT32_MAX) return INT32_MAX;
        return (int)factor;
    }

    unsigned int mulFrac2Int(unsigned_frac_t a, unsigned_frac_t b) {
        uint64_t factor = (uint64_t)a.factor * (uint64_t)b.factor;
        uint64_t divisor = (uint64_t)a.divisor * (uint64_t)b.divisor;
        factor /= divisor;
        if (factor > UINT32_MAX) return UINT32_MAX;
        return (unsigned int)factor;
    }

    unsigned int gcd(unsigned int a, unsigned int b) {
        unsigned int r;
        while ((a % b) > 0U)  {
            r = a % b;
            a = b;
            b = r;
        }
        return b;
    }

    void minimize(frac_t* frac) {
        unsigned int common_div = gcd(frac->factor, frac->divisor);
        frac->factor /= common_div;
        frac->divisor /= common_div;
    }

    void minimize(unsigned_frac_t* frac) {
        unsigned int common_div = gcd(frac->factor, frac->divisor);
        frac->factor /= common_div;
        frac->divisor /= common_div;
    }
}