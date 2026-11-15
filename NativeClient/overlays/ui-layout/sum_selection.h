// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef EDOPRO_SUM_SELECTION_H
#define EDOPRO_SUM_SELECTION_H
#include <algorithm>
#include <cstdint>
#include <map>
#include <vector>

namespace ygo::sumselection {
struct Contribution {
    std::uint32_t minimum, maximum;
    bool supported;
    explicit Contribution(std::uint32_t packed) {
        // The core decodes the high half as signed. This helper supports nonnegative
        // contributions only; negative alternate values need a different subset algorithm.
        supported = (packed & 0x80000000u) == 0;
        const auto first = packed & 0xffffu, second = packed >> 16;
        minimum = second ? std::min(first, second) : first;
        maximum = std::max(first, second);
    }
};
struct GreaterSum {
    std::uint64_t minimumSum = 0, maximumSum = 0;
    std::uint32_t smallest = 0;
    bool hasCards = false, supported = true;
    void Add(std::uint32_t packed) {
        const Contribution value(packed);
        if(!value.supported) { supported = false; return; }
        smallest = hasCards ? std::min(smallest, value.minimum) : value.minimum;
        minimumSum += value.minimum;
        maximumSum += value.maximum;
        hasCards = true;
    }
    bool IsComplete(std::uint32_t target) const {
        // Pinned core playerop.cpp SelectSum mode 1 predicate, within the nonnegative domain.
        return supported && maximumSum >= target && (!hasCards || minimumSum - smallest < target);
    }
};

inline bool CanCompleteGreater(const GreaterSum& fixed, const std::vector<std::uint32_t>& remaining,
                               std::uint32_t target) {
    if(!fixed.supported) return false;
    std::vector<Contribution> available;
    available.reserve(remaining.size());
    auto possible = fixed.maximumSum;
    for(auto packed : remaining) {
        available.emplace_back(packed);
        // Fail closed for an unsupported remaining value rather than misinterpreting it as a large positive one.
        if(!available.back().supported) return false;
        possible += available.back().maximum;
    }
    if(fixed.IsComplete(target)) return true;
    // Adding nonnegative cards cannot lower this penalty, so a redundant set cannot recover.
    if(fixed.hasCards && fixed.minimumSum - fixed.smallest >= target) return false;
    if(possible < target || available.empty()) return false;
    std::sort(available.begin(), available.end(), [](const auto& left, const auto& right) {
        return left.minimum > right.minimum;
    });
    const auto needed = target - fixed.maximumSum;
    const auto baseSmallest = fixed.hasCards ? fixed.smallest : available.front().minimum;
    const std::uint64_t capacity = std::uint64_t(target) - 1 + baseSmallest - fixed.minimumSum;
    // Sparse knapsack: cost is the sum of minimum values; score is maximum contribution.
    // No allocation depends directly on a wire-supplied target. Dominated states are discarded.
    std::map<std::uint64_t, std::uint64_t> frontier{{0, 0}};
    for(const auto& value : available) {
        const auto smallest = fixed.hasCards ? std::min(fixed.smallest, value.minimum) : value.minimum;
        const auto cost = fixed.minimumSum + value.minimum;
        const std::uint64_t ceiling = std::uint64_t(target) - 1 + smallest;
        // All previously processed cards have >= this minimum. Include this card as the smallest
        // new one, then ask which subset of those previous cards fits the exact core minimality rule.
        if(cost <= ceiling) {
            auto best = frontier.upper_bound(ceiling - cost);
            if(best != frontier.begin() && (--best)->second + value.maximum >= needed) return true;
        }
        if(value.minimum > capacity) continue;
        auto next = frontier;
        for(const auto& state : frontier) {
            const auto newCost = state.first + value.minimum;
            if(newCost > capacity) break;
            auto& score = next[newCost];
            score = std::max(score, std::min(needed, state.second + value.maximum));
        }
        std::uint64_t bestScore = 0;
        bool first = true;
        for(auto it = next.begin(); it != next.end();) {
            if(!first && it->second <= bestScore) it = next.erase(it);
            else { bestScore = it->second; first = false; ++it; }
        }
        frontier.swap(next);
    }
    return false;
}
}
#endif
