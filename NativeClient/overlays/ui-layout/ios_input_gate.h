// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef EDOPRO_IOS_INPUT_GATE_H
#define EDOPRO_IOS_INPUT_GATE_H
#include <cstdint>

namespace porting {
// The bridge protects this state with its mutex; at most one native input dialog is current.
class NativeInputGate {
    uint64_t sequence = 0, current = 0;
    bool active = false;
public:
    void Start() { active = true; current = 0; }
    void Stop() { active = false; current = 0; }
    uint64_t Begin() {
        if(!active || current) return 0;
        if(++sequence == 0) ++sequence;
        return current = sequence;
    }
    bool Accepts(uint64_t token) const { return active && token && token == current; }
    bool Finish(uint64_t token) {
        if(!Accepts(token)) return false;
        current = 0;
        return true;
    }
    uint64_t Cancel() { const auto token = current; current = 0; return token; }
};
}
#endif
