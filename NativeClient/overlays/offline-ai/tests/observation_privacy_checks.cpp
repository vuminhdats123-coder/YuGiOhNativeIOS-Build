// Authored only; native compilation/execution is deferred under the build hold.
// Uses the production policy. Supply the normal gframe/config include paths when compiling later.
#include "../OfflineAI.h"
#include <cassert>

int main() {
    using ygo::OfflineAI::CopyPublicObservation;
    std::vector<uint8_t> output, secret(32, 0xa5);
    for(const auto message : {30, 31, 32, 33, 35, 38, 39, 50, 90, 111}) {
        assert(!CopyPublicObservation(1, message, secret.data(), secret.size(), output));
        assert(output.empty());
    }
    std::vector<uint8_t> hint(10, 0);
    hint[0] = 3; hint[1] = 1; hint[2] = 0xfd; hint[3] = 1; // Public HINTMSG_SPSUMMON 509.
    assert(CopyPublicObservation(1, 2, hint.data(), hint.size(), output) && output == hint);
    assert(!CopyPublicObservation(0, 2, hint.data(), hint.size(), output));
    hint[0] = 2; // Other hint families may carry identifiers the strategy does not need.
    assert(!CopyPublicObservation(1, 2, hint.data(), hint.size(), output));
    assert(!CopyPublicObservation(1, 2, nullptr, 10, output));
    assert(!CopyPublicObservation(1, 2, hint.data(), 9, output));

    std::vector<uint8_t> summon(14, 0);
    summon[0] = 123; summon[4] = 0; summon[5] = 4; summon[10] = 8;
    for(const auto message : {60, 62, 64}) {
        assert(CopyPublicObservation(1, message, summon.data(), summon.size(), output));
        assert(output[0] == 0 && output[1] == 0 && output[2] == 0 && output[3] == 0);
        assert(output[4] == summon[4] && output[10] == 8);
    }
    summon[10] = 1;
    assert(CopyPublicObservation(1, 62, summon.data(), summon.size(), output) && output == summon);

    std::vector<uint8_t> chain(32, 0);
    chain[0] = 123; chain[4] = 0; chain[14] = 0;
    for(const auto location : {1, 2, 64}) {
        chain[5] = chain[15] = location;
        std::fill(chain.begin() + 6, chain.begin() + 10, 0xa5);
        std::fill(chain.begin() + 16, chain.begin() + 20, 0x5a);
        assert(CopyPublicObservation(1, 70, chain.data(), chain.size(), output));
        assert(output[0] == 123); // Declared effect identity is public; private pile order is not.
        for(std::size_t index = 6; index < 10; ++index) assert(output[index] == 0);
        for(std::size_t index = 16; index < 20; ++index) assert(output[index] == 0);
    }
    chain[5] = 4; chain[15] = 8;
    assert(CopyPublicObservation(1, 70, chain.data(), chain.size(), output) && output == chain);
    assert(!CopyPublicObservation(1, 70, chain.data(), chain.size() - 1, output));
    const uint8_t chainIndex[] = {1, 0, 0, 0};
    for(const auto message : {71, 72, 73, 75, 76}) {
        assert(CopyPublicObservation(1, message, chainIndex, 1, output) && output == std::vector<uint8_t>{1});
        assert(!CopyPublicObservation(1, message, chainIndex, 4, output));
    }
    for(const auto message : {61, 63, 65, 74, 113, 114})
        assert(CopyPublicObservation(1, message, nullptr, 0, output) && output.empty());
    assert(!CopyPublicObservation(2, 74, nullptr, 0, output));
}
