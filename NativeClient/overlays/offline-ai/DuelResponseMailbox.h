// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef EDOPRO_DUEL_RESPONSE_MAILBOX_H
#define EDOPRO_DUEL_RESPONSE_MAILBOX_H
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <utility>
#include <vector>

namespace ygo {
// A response may arrive before the duel thread starts waiting. Stop stays latched until Reset.
class DuelResponseMailbox {
    std::mutex mutex;
    std::condition_variable changed;
    bool stopped = true, accepting = false, ready = false;
    std::vector<uint8_t> response;
public:
    void Reset() {
        std::lock_guard<std::mutex> lock(mutex);
        stopped = accepting = ready = false;
        response.clear();
    }
    bool Begin() {
        std::lock_guard<std::mutex> lock(mutex);
        if(stopped) return false;
        accepting = true;
        ready = false;
        response.clear();
        return true;
    }
    bool Submit(const void* bytes, size_t length) {
        if(!bytes || length == 0 || length > 65536) return false;
        std::lock_guard<std::mutex> lock(mutex);
        if(stopped || !accepting || ready) return false;
        const auto* data = static_cast<const uint8_t*>(bytes);
        response.assign(data, data + length);
        ready = true;
        changed.notify_one();
        return true;
    }
    bool Receive(std::vector<uint8_t>& result) {
        std::unique_lock<std::mutex> lock(mutex);
        changed.wait(lock, [this] { return stopped || ready; });
        accepting = false;
        if(stopped) return false;
        result = std::move(response);
        ready = false;
        return true;
    }
    void Stop() {
        std::lock_guard<std::mutex> lock(mutex);
        stopped = true;
        accepting = ready = false;
        response.clear();
        changed.notify_all();
    }
};
}
#endif
