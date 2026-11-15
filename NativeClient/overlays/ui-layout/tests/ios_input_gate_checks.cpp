// Production gate assertions; authored only while native compilation is held.
#include "../ios_input_gate.h"
#include <cassert>

int main() {
    porting::NativeInputGate gate;
    assert(gate.Begin() == 0);
    gate.Start();
    const auto first = gate.Begin();
    assert(first && gate.Accepts(first) && gate.Begin() == 0);
    assert(!gate.Finish(first + 1) && gate.Accepts(first));
    assert(gate.Finish(first) && !gate.Finish(first));
    const auto second = gate.Begin();
    assert(second != first && !gate.Accepts(first));
    assert(gate.Cancel() == second && !gate.Accepts(second));
    const auto third = gate.Begin();
    gate.Stop();
    assert(!gate.Accepts(third) && !gate.Finish(third) && gate.Begin() == 0);
    gate.Start();
    const auto nextSession = gate.Begin();
    assert(nextSession != third && !gate.Accepts(third));
    assert(gate.Finish(nextSession));
}
