#ifndef EDOPRO_OFFLINE_AI_H
#define EDOPRO_OFFLINE_AI_H
#include "config.h"
#include "text_types.h"
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

class Duel;
namespace ygo {
struct Deck;
namespace OfflineAI {
constexpr int MENU_OPEN = 30001, MENU_START = 30002, MENU_CANCEL = 30003;
// Restrict delivery before JS.observe. Unknown/private event families never reach the bot.
// The wire sizes below are from the pinned API 11 core; draw/hand/deck-order events are excluded.
inline bool CopyPublicObservation(uint8_t player, uint8_t message, const uint8_t* data,
                                  std::size_t size, std::vector<uint8_t>& output) {
    output.clear();
    if(player > 1 || (size && !data)) return false;
    std::size_t expected;
    switch(message) {
    case 2: expected = 10; break;                    // HINT_SELECTMSG, checked below
    case 40: expected = 1; break;                   // NEW_TURN
    case 41: expected = 2; break;                   // NEW_PHASE
    case 60: case 62: case 64: expected = 14; break; // SUMMONING / SPSUMMONING / FLIPSUMMONING
    case 61: case 63: case 65: case 74:
    case 113: case 114: expected = 0; break;         // Completion / chain end / Damage Step boundary
    case 70: expected = 32; break;                  // Publicly declared chain effect
    case 71: case 72: case 73: case 75: case 76: expected = 1; break;
    case 110: expected = 20; break;                 // ATTACK: locations, no identities or stats
    default: return false;
    }
    if(size != expected || (message == 2 && (data[0] != 3 || data[1] != player))) return false;
    if(size) output.assign(data, data + size);
    if((message == 60 || message == 62 || message == 64) && !(output[10] & 5))
        std::fill_n(output.begin(), 4, uint8_t(0));
    if(message == 70) {
        // An activated effect's identity is public; its location in a private pile is not.
        const auto privateLocation = [](uint8_t location) { return location == 1 || location == 2 || location == 64; };
        if(privateLocation(output[5])) std::fill_n(output.begin() + 6, 4, uint8_t(0));
        if(privateLocation(output[15])) std::fill_n(output.begin() + 16, 4, uint8_t(0));
    }
    return true;
}
#if EDOPRO_IOS
bool Start(std::string& error);
void Stop();
bool Handles(uint8_t message);
bool Observe(uint8_t message, const uint8_t* data, size_t size, std::string& error);
// decide's fifth argument is a relative self/opponent snapshot: LP, public zone counts and
// on-field cards, plus the AI's own hand/Extra identities and both public Grave arrays.
// Opponent hand/Extra and Main Deck identities/order are omitted. Face-down field records
// contain no identity/stats; own legal selection/search candidates still come from the prompt.
bool Respond(const ::Duel* duel, uint8_t message, const uint8_t* data, size_t size, std::vector<uint8_t>& response, std::string& error);
// Human ClientAnalyze needs real deck sequences for GetCard; only decision input hides deck order.
bool FilterForHuman(uint8_t message, const uint8_t* data, size_t size, std::vector<uint8_t>& filtered, bool& visible, std::string& error, bool hideDeckOrder = false);
bool LoadDeck(epro::path_stringview name, Deck& output, std::string& error);
#else
inline bool Start(std::string& error) { error = "Offline AI requires the iOS JavaScriptCore adapter."; return false; }
inline void Stop() {}
inline bool Handles(uint8_t) { return false; }
inline bool Observe(uint8_t, const uint8_t*, size_t, std::string&) { return true; }
inline bool Respond(const ::Duel*, uint8_t, const uint8_t*, size_t, std::vector<uint8_t>&, std::string&) { return false; }
inline bool FilterForHuman(uint8_t, const uint8_t*, size_t, std::vector<uint8_t>&, bool&, std::string&, bool = false) { return false; }
inline bool LoadDeck(epro::path_stringview, Deck&, std::string& error) { error = "Offline AI is currently iOS-only."; return false; }
#endif
}
}
#endif
