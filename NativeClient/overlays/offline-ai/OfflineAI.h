#ifndef EDOPRO_OFFLINE_AI_H
#define EDOPRO_OFFLINE_AI_H
#include "config.h"
#include "text_types.h"
#include <cstdint>
#include <string>
#include <vector>

namespace ygo {
struct Deck;
namespace OfflineAI {
constexpr int MENU_OPEN = 30001, MENU_START = 30002, MENU_CANCEL = 30003;
#if EDOPRO_IOS
bool Start(std::string& error);
void Stop();
bool Handles(uint8_t message);
bool Observe(uint8_t message, const uint8_t* data, size_t size, std::string& error);
bool Respond(uint8_t message, const uint8_t* data, size_t size, std::vector<uint8_t>& response, std::string& error);
bool FilterForHuman(uint8_t message, const uint8_t* data, size_t size, std::vector<uint8_t>& filtered, bool& visible, std::string& error);
bool LoadDeck(epro::path_stringview name, Deck& output, std::string& error);
#else
inline bool Start(std::string& error) { error = "Offline AI requires the iOS JavaScriptCore adapter."; return false; }
inline void Stop() {}
inline bool Handles(uint8_t) { return false; }
inline bool Observe(uint8_t, const uint8_t*, size_t, std::string&) { return true; }
inline bool Respond(uint8_t, const uint8_t*, size_t, std::vector<uint8_t>&, std::string&) { return false; }
inline bool FilterForHuman(uint8_t, const uint8_t*, size_t, std::vector<uint8_t>&, bool&, std::string&) { return false; }
inline bool LoadDeck(epro::path_stringview, Deck&, std::string& error) { error = "Offline AI is currently iOS-only."; return false; }
#endif
}
}
#endif
