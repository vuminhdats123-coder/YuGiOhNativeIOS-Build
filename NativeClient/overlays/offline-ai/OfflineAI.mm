// SPDX-License-Identifier: AGPL-3.0-or-later
#import <JavaScriptCore/JavaScriptCore.h>
#include "../OfflineAI.h"
#include "../data_manager.h"
#include "../deck_manager.h"
#include "../file_stream.h"
#include "../game.h"
#include "../client_card.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <unordered_map>

namespace ygo::OfflineAI {
namespace {
// Owned and used exclusively by SinglePlayThread, never by the GUI thread.
JSContext* context = nil;
JSValue* bot = nil;
bool checkError(std::string& error) {
	if(!context || !bot) { error = "Offline AI was not initialized."; return false; }
	if(context.exception) {
		error = context.exception.toString.UTF8String ?: "JavaScriptCore AI exception";
		context.exception = nil;
		return false;
	}
	return true;
}
NSArray* bytes(const uint8_t* data, size_t size) {
	NSMutableArray* array = [NSMutableArray arrayWithCapacity:size];
	for(size_t i = 0; i < size; ++i) [array addObject:@(data[i])];
	return array;
}
bool readBytes(JSValue* value, std::vector<uint8_t>& out, std::string& error) {
	if(!checkError(error)) return false;
	if(!value.isArray) { error = "AI returned a non-array response."; return false; }
	NSArray* array = value.toArray;
	if(array.count > 1048576) { error = "AI response exceeds size limit."; return false; }
	out.clear(); out.reserve(array.count);
	for(id entry in array) {
		if(![entry isKindOfClass:[NSNumber class]]) { error = "Invalid AI response byte."; return false; }
		const auto number = [entry doubleValue];
		if(!std::isfinite(number) || number < 0 || number > 255 || std::floor(number) != number) {
			error = "AI response contains an invalid byte."; return false;
		}
		out.push_back(static_cast<uint8_t>(number));
	}
	return true;
}
NSDictionary* queriedCard(const ::Duel* duel, uint8_t controller, uint32_t location, uint32_t sequence) {
	if(!duel) return nil;
	constexpr uint32_t queryFlags = 0x1u | 0x2u | 0x8u | 0x10u | 0x20u | 0x100u | 0x200u | 0x80000u | 0x800000u;
	OCG_QueryInfo query{queryFlags, controller, location, sequence, 0};
	uint32_t length = 0;
	const auto* raw = static_cast<const uint8_t*>(duel->DuelQuery(&length, &query));
	if(!raw || length == 0) return nil;
	uint32_t code = 0, position = 0, type = 0, level = 0, rank = 0, link = 0, status = 0;
	int32_t attack = 0, defense = 0;
	size_t at = 0;
	while(at + sizeof(uint16_t) <= length) {
		const auto size = static_cast<uint16_t>(raw[at] | (uint16_t(raw[at + 1]) << 8)); at += sizeof(uint16_t);
		if(size < sizeof(uint32_t) || at + size > length) return nil;
		const uint32_t flag = uint32_t(raw[at]) | (uint32_t(raw[at + 1]) << 8) | (uint32_t(raw[at + 2]) << 16) | (uint32_t(raw[at + 3]) << 24);
		at += sizeof(uint32_t);
		const auto read32 = [&]() -> uint32_t {
			if(at + sizeof(uint32_t) > length || at + sizeof(uint32_t) > at + size - sizeof(uint32_t)) return 0;
			const uint32_t value = uint32_t(raw[at]) | (uint32_t(raw[at + 1]) << 8) | (uint32_t(raw[at + 2]) << 16) | (uint32_t(raw[at + 3]) << 24); at += sizeof(uint32_t); return value;
		};
		switch(flag) {
		case 0x1u: code = read32(); break; case 0x2u: position = read32(); break; case 0x8u: type = read32(); break;
		case 0x10u: level = read32(); break; case 0x20u: rank = read32(); break; case 0x100u: attack = static_cast<int32_t>(read32()); break;
		case 0x200u: defense = static_cast<int32_t>(read32()); break; case 0x80000u: status = read32(); break; case 0x800000u: link = read32(); read32(); break;
		default: at += size - sizeof(uint32_t); break;
		}
		const size_t recordEnd = at; if(recordEnd < at) return nil;
	}
	if(!code) return nil;
	return @{@"code":@(code), @"location":@(location), @"sequence":@(sequence), @"position":@(position), @"type":@(type),
		@"attack":@(attack), @"defense":@(defense), @"level":@(level), @"rank":@(rank), @"link":@(link), @"disabled":@((status & 1u) != 0)};
}
NSArray* queriedZone(const ::Duel* duel, uint8_t controller, uint32_t location, uint32_t count) {
	NSMutableArray* result = [NSMutableArray array];
	// Hand/Extra are bounded by deck rules; public Grave can grow through effects, so cap bridge work.
	const uint32_t limit = std::min<uint32_t>(count, 256);
	for(uint32_t sequence = 0; sequence < limit; ++sequence) {
		if(NSDictionary* card = queriedCard(duel, controller, location, sequence)) [result addObject:card];
	}
	return result;
}
NSDictionary* ownAndPublicZones(const ::Duel* duel) {
	if(!duel) return @{};
	NSMutableDictionary* result = [NSMutableDictionary dictionary];
	const auto count = [&](uint8_t controller, uint32_t location) { return duel->DuelQueryCount(controller, location); };
	[result setObject:queriedZone(duel, 1, LOCATION_HAND, count(1, LOCATION_HAND)) forKey:@"hand"];
	[result setObject:queriedZone(duel, 1, LOCATION_EXTRA, count(1, LOCATION_EXTRA)) forKey:@"extra"];
	[result setObject:queriedZone(duel, 1, LOCATION_GRAVE, count(1, LOCATION_GRAVE)) forKey:@"selfGrave"];
	[result setObject:queriedZone(duel, 0, LOCATION_GRAVE, count(0, LOCATION_GRAVE)) forKey:@"opponentGrave"];
	return result;
}
// Caller holds gMutex. dField uses the human/render perspective, so translate every core player.
NSDictionary* publicBoardSide(uint8_t corePlayer) {
	const auto local = mainGame->LocalPlayer(corePlayer);
	NSMutableArray* cards = [NSMutableArray array];
	const auto appendZone = [&](const auto& zone, uint32_t location) {
		for(const auto* card : zone) if(card) {
			NSMutableDictionary* entry = [NSMutableDictionary dictionaryWithDictionary:@{
				@"code":@0, @"location":@(location), @"sequence":@(card->sequence), @"position":@(card->position)}];
			// Do not trust remembered code/stats for a card that has since been turned face-down.
			if((card->position & POS_FACEUP) && card->code) {
				[entry addEntriesFromDictionary:@{@"code":@(card->code), @"type":@(card->type),
					@"attack":@(card->attack), @"defense":@(card->defense), @"level":@(card->level),
					@"rank":@(card->rank), @"link":@(card->link), @"disabled":@((card->status & STATUS_DISABLED) != 0)}];
			}
			[cards addObject:entry];
		}
	};
	appendZone(mainGame->dField.mzone[local], LOCATION_MZONE);
	appendZone(mainGame->dField.szone[local], LOCATION_SZONE);
	// Counts are public. Never enumerate hand, deck or Extra Deck identities/order for the bot.
	return @{@"lp":@(mainGame->dInfo.lp[local]), @"handCount":@(mainGame->dField.hand[local].size()),
		@"deckCount":@(mainGame->dField.deck[local].size()), @"extraCount":@(mainGame->dField.extra[local].size()), @"cards":cards};
}
}

bool Start(std::string& error) {
	Stop();
	@autoreleasepool {
		NSError* failure = nil;
		NSString* script = [NSString stringWithContentsOfFile:@"./offline-ai/offline_ai.js" encoding:NSUTF8StringEncoding error:&failure];
		if(!script) { error = failure.localizedDescription.UTF8String ?: "Missing offline AI script."; return false; }
		context = [[JSContext alloc] init];
		[context evaluateScript:script];
		if(context.exception) { error = context.exception.toString.UTF8String; Stop(); return false; }
		NSMutableDictionary* metadata = [NSMutableDictionary dictionary];
		for(const auto& item : gDataManager->cards) {
			const auto& card = item.second._data;
			metadata[[NSString stringWithFormat:@"%u", card.code]] = @{@"attack":@(card.attack), @"defense":@(card.defense), @"type":@(card.type), @"level":@(card.level)};
		}
		bot = [[context[@"OfflineDuelAI"][@"create"] callWithArguments:@[metadata]] retain];
		if(!checkError(error)) { Stop(); return false; }
		if(bot.isUndefined || bot.isNull) { error = "Offline AI factory returned no instance."; Stop(); return false; }
		return true;
	}
}
void Stop() { [bot release]; bot = nil; [context release]; context = nil; }
bool Handles(uint8_t message) {
	switch(message) {
	case 10: case 11: case 12: case 13: case 14: case 15: case 16: case 18: case 19: case 20:
	case 21: case 22: case 23: case 24: case 25: case 26: case 132: case 140: case 141: case 142: case 143: return true;
	default: return false;
	}
}
bool Observe(uint8_t message, const uint8_t* data, size_t size, std::string& error) {
	std::vector<uint8_t> publicData;
	if(!CopyPublicObservation(1, message, data, size, publicData)) return true;
	@autoreleasepool {
		[bot invokeMethod:@"observe" withArguments:@[@(message), bytes(publicData.data(), publicData.size())]];
		return checkError(error);
	}
}
bool FilterForHuman(uint8_t message, const uint8_t* data, size_t size, std::vector<uint8_t>& filtered, bool& visible, std::string& error, bool hideDeckOrder) {
	@autoreleasepool {
		JSValue* result = [bot invokeMethod:@"forHuman" withArguments:@[@(message),bytes(data,size),@(hideDeckOrder)]];
		if(!checkError(error)) return false;
		visible = !result.isNull;
		return !visible || readBytes(result, filtered, error);
	}
}
bool Respond(const ::Duel* duel, uint8_t message, const uint8_t* data, size_t size, std::vector<uint8_t>& response, std::string& error) {
	if(!Handles(message) || size == 0 || !data || data[0] != 1) { error = "AI must respond only to player 1 prompts."; return false; }
	// Despite its historical name, selector redaction is relative to the prompt's selecting player.
	// Keep legal search/public identities and wire indices; conceal opposing hidden identities.
	std::vector<uint8_t> prompt;
	bool visible = false;
	if(!FilterForHuman(message, data, size, prompt, visible, error, true)) return false;
	if(!visible) { error = "AI selection prompt was hidden by the privacy filter."; return false; }
	@autoreleasepool {
		NSMutableArray* declarable = [NSMutableArray array];
		if(message == MSG_ANNOUNCE_CARD) {
			if(size < 2 || size != 2 + static_cast<size_t>(data[1]) * sizeof(uint64_t)) { error = "Malformed announce-card prompt."; return false; }
			std::vector<uint64_t> opcodes(data[1]);
			std::memcpy(opcodes.data(), data + 2, opcodes.size() * sizeof(uint64_t));
			std::vector<uint32_t> codes;
			for(const auto& item : gDataManager->cards)
				if(DataManager::IsCardDeclarable(&item.second._data, opcodes, false)) codes.push_back(item.first);
			std::sort(codes.begin(), codes.end());
			for(auto code : codes) [declarable addObject:@(code)];
		}
		NSMutableDictionary* positions = [NSMutableDictionary dictionary];
		NSMutableDictionary* selfState;
		NSMutableDictionary* opponentState;
		{
			std::lock_guard<epro::mutex> lock(mainGame->gMutex);
			for(auto* card : mainGame->dField.mzone[mainGame->LocalPlayer(1)]) if(card)
				positions[[NSString stringWithFormat:@"%u", card->sequence]] = @(card->position);
			selfState = [NSMutableDictionary dictionaryWithDictionary:publicBoardSide(1)];
			opponentState = [NSMutableDictionary dictionaryWithDictionary:publicBoardSide(0)];
			const auto zones = ownAndPublicZones(duel);
			selfState[@"hand"] = zones[@"hand"];
			selfState[@"extra"] = zones[@"extra"];
			selfState[@"grave"] = zones[@"selfGrave"];
			opponentState[@"grave"] = zones[@"opponentGrave"];
		}
		NSDictionary* state = @{@"self":selfState, @"opponent":opponentState};
		JSValue* result = [bot invokeMethod:@"decide" withArguments:@[@(message),bytes(prompt.data(),prompt.size()),declarable,positions,state]];
		if(!checkError(error)) return false;
		if(![result[@"handled"] toBool]) { error = "Offline AI did not handle the engine prompt."; return false; }
		if(!readBytes(result[@"response"], response, error)) return false;
		if(response.empty() || response.size() > 65536) { error = "Empty or oversized AI response."; return false; }
		return true;
	}
}

bool LoadDeck(epro::path_stringview name, Deck& output, std::string& error) {
	FileStream input{DeckManager::GetDeckPath(name), FileStream::in};
	if(input.fail()) { error = "Cannot open selected YDK deck."; return false; }
	Deck validated;
	Deck::Vector* zone = &validated.main;
	std::unordered_map<uint32_t, int> counts;
	std::string line;
	while(std::getline(input, line)) {
		if(!line.empty() && line.back() == '\r') line.pop_back();
		if(line.empty()) continue;
		if(line == "#main") { zone = &validated.main; continue; }
		if(line == "#extra") { zone = &validated.extra; continue; }
		if(line == "!side") { zone = &validated.side; continue; }
		if(line[0] == '#') continue;
		if(line.find_first_not_of("0123456789") != std::string::npos) { error = "Invalid YDK card code."; return false; }
		uint64_t code;
		try { code = std::stoull(line); } catch(...) { error = "Invalid YDK card code."; return false; }
		const auto* card = code <= std::numeric_limits<uint32_t>::max() ? gDataManager->GetCardData(static_cast<uint32_t>(code)) : nullptr;
		if(!card || !card->code || (card->type & (TYPE_TOKEN | TYPE_SKILL)) || card->isRush()) { error = "Unknown or unsupported-format card in selected deck."; return false; }
		const bool extra = (card->type & (TYPE_FUSION | TYPE_SYNCHRO | TYPE_XYZ | TYPE_LINK)) != 0;
		if(zone != &validated.side && (extra != (zone == &validated.extra))) { error = "Main/Extra deck card location is invalid."; return false; }
		if(++counts[card->alias ? card->alias : card->code] > 3) { error = "More than three copies of a card in selected deck."; return false; }
		zone->push_back(card);
		if(validated.main.size() > 60 || validated.extra.size() > 15 || validated.side.size() > 15) { error = "Deck size limit exceeded."; return false; }
	}
	if(validated.main.size() < 40) { error = "Main Deck needs at least 40 cards."; return false; }
	output = std::move(validated);
	return true;
}
}
