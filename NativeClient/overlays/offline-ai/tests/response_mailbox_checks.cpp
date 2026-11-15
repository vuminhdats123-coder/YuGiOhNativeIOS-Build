// Tests the actual production mailbox; native compilation/execution is deferred while builds are held.
#include "../DuelResponseMailbox.h"
#include <cassert>
#include <chrono>
#include <future>

int main() {
    ygo::DuelResponseMailbox mailbox;
    const uint8_t answer[] = {1, 0, 0, 0};
    std::vector<uint8_t> received;
    assert(!mailbox.Begin());
    mailbox.Reset();
    assert(!mailbox.Submit(answer, sizeof(answer)));
    assert(mailbox.Begin());
    // This sequence used to lose the notify and hang: answer arrives before Receive.
    assert(mailbox.Submit(answer, sizeof(answer)));
    assert(!mailbox.Submit(answer, sizeof(answer)));
    assert(mailbox.Receive(received) && received == std::vector<uint8_t>(answer, answer + 4));
    assert(mailbox.Begin());
    auto waiting = std::async(std::launch::async, [&] { return mailbox.Receive(received); });
    mailbox.Stop();
    assert(waiting.wait_for(std::chrono::seconds(2)) == std::future_status::ready);
    assert(!waiting.get());
    assert(!mailbox.Begin() && !mailbox.Submit(answer, sizeof(answer)));
    mailbox.Reset();
    assert(mailbox.Begin());
    assert(mailbox.Submit(answer, sizeof(answer)));
    mailbox.Stop();
    assert(!mailbox.Receive(received)); // Stop supersedes a queued response.
}
