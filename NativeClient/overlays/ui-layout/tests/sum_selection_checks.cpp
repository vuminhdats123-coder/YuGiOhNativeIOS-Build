// Authored only: no native compilation/execution while the build hold is active.
// Calls the same production helper as ClientField::CheckSelectSum mode 1.
#include "../sum_selection.h"
#include <cassert>
#include <limits>

namespace {
constexpr std::uint32_t Packed(std::uint32_t first, std::uint32_t second) {
    return first | (second << 16);
}
ygo::sumselection::GreaterSum Fixed(const std::vector<std::uint32_t>& values) {
    ygo::sumselection::GreaterSum result;
    for(auto value : values) result.Add(value);
    return result;
}
// Independent exhaustive subset oracle using pinned playerop.cpp's acceptance predicate,
// rather than the production knapsack or a second recursive completion algorithm.
bool CoreAccepts(const std::vector<std::uint32_t>& values, std::uint32_t target) {
    std::int64_t sum = 0, maximum = 0, smallest = std::numeric_limits<std::int32_t>::max();
    for(auto value : values) {
        const std::int64_t first = value & 0xffffu;
        // Reproduce the core's signed int32_t arithmetic shift without relying on a narrowing cast.
        const std::int64_t second = (value & 0x80000000u) ? std::int64_t(value >> 16) - 0x10000 : value >> 16;
        const auto minimum = second && second < first ? second : first;
        sum += minimum;
        maximum += std::max(first, second);
        smallest = std::min(smallest, minimum);
    }
    return maximum >= target && sum - smallest < target;
}
bool AnyCoreSubset(const std::vector<std::uint32_t>& fixed, const std::vector<std::uint32_t>& optional,
                   std::uint32_t target) {
    for(std::uint32_t mask = 0; mask < (1u << optional.size()); ++mask) {
        auto selected = fixed;
        for(std::size_t i = 0; i < optional.size(); ++i)
            if(mask & (1u << i)) selected.push_back(optional[i]);
        if(CoreAccepts(selected, target)) return true;
    }
    return false;
}
}

int main() {
    using namespace ygo::sumselection;
    // Previously neither optional card was selectable, although the core accepts both at their high values.
    assert(CanCompleteGreater(Fixed({Packed(1, 4)}), {Packed(1, 4)}, 8));
    assert(Fixed({Packed(1, 4), Packed(1, 4)}).IsComplete(8));
    assert(CanCompleteGreater(Fixed({Packed(4, 1)}), {Packed(4, 1)}, 8));
    assert(!CanCompleteGreater(Fixed({8, 1}), {Packed(1, 8)}, 8));
    assert(!Fixed({3, 5, 1}).IsComplete(8));
    assert(Fixed({3, 5}).IsComplete(8));
    assert(CanCompleteGreater(Fixed({3}), {5}, 8));
    assert(!CanCompleteGreater(Fixed({1}), {1, 2}, 8));
    assert(CanCompleteGreater(Fixed({Packed(0, 4)}), {Packed(0, 4)}, 8));
    assert(CanCompleteGreater(Fixed({Packed(8, 10)}), {Packed(0, 4)}, 12));
    assert(!CanCompleteGreater(Fixed({8, Packed(0, 4)}), {5}, 8));
    assert(CanCompleteGreater(Fixed({}), {}, 0));
    assert(!CanCompleteGreater(Fixed({1}), {}, 0));
    assert(!CanCompleteGreater(Fixed({1}), {Packed(65535, 32767), Packed(65535, 32767)},
        std::numeric_limits<std::uint32_t>::max()));
    // Unsupported negative high halves fail closed; equivalence to core is only claimed for nonnegative values.
    assert(!Fixed({0x80000001u}).IsComplete(1));
    assert(!CanCompleteGreater(Fixed({0x80000001u}), {8}, 8));
    assert(!CanCompleteGreater(Fixed({1}), {0x80000001u, 8}, 8));

    const std::vector<std::vector<std::uint32_t>> fixedSets{
        {}, {1}, {3, 1}, {Packed(1, 4)}, {Packed(2, 5), 1}, {Packed(0, 3)}};
    const std::uint32_t alphabet[]{0, 1, 4, Packed(1, 4), Packed(0, 3)};
    for(std::size_t count = 0, variants = 1; count <= 4; ++count, variants *= 5) {
        for(std::size_t encoded = 0; encoded < variants; ++encoded) {
            auto digits = encoded;
            std::vector<std::uint32_t> optional;
            for(std::size_t i = 0; i < count; ++i, digits /= 5) optional.push_back(alphabet[digits % 5]);
            for(const auto& fixed : fixedSets) for(std::uint32_t target = 0; target <= 12; ++target) {
                assert(Fixed(fixed).IsComplete(target) == CoreAccepts(fixed, target));
                assert(CanCompleteGreater(Fixed(fixed), optional, target) == AnyCoreSubset(fixed, optional, target));
            }
        }
    }
}
