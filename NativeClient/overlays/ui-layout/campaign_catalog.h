// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef EDOPRO_CAMPAIGN_CATALOG_H
#define EDOPRO_CAMPAIGN_CATALOG_H

#include <array>
#include <algorithm>
#include <fstream>
#include <string>
#include <string_view>
#include <nlohmann/json.hpp>

namespace ygo::campaignui {
struct Stage {
	std::string title;
	std::string deckKey;
	std::string icon;
	int unlockAfterWins = 0;
};

inline std::array<Stage, 10> Defaults() {
	return {{
		{"Stage 1-1", "OBB_NPC-TeaGardner-A_1840e9a418", "icon_YGOMD_First_Tea.png", 0},
		{"Stage 1-2", "OBB_NPC-SolomonMuto-A_991f6181e7", "icon_YGOMD_First_Solomon.png", 1},
		{"Stage 1-3", "OBB_NPC-WeevilUnderwood-A_05ec7cda94", "icon_YGOMD_First_Weevil.png", 2},
		{"Stage 1-4", "OBB_NPC-BanditKeith-A_d2a2f75abc", "icon_YGOMD_First_Keith.png", 3},
		{"Stage 1-5", "OBB_NPC-MaximillionPegasus-A_8513ed0de6", "icon_YGOMD_First_Pegasus.png", 4},
		{"Stage 2-1", "OBB_NPC-YamiYugi-A_e237a13630", "icon_YGOMD_First_YamiYugi.png", 5},
		{"Stage 2-2", "OBB_NPC-JoeyWheeler-A_c5dfe7b5a6", "icon_YGOMD_First_joey.png", 6},
		{"Stage 2-3", "OBB_NPC-SetoKaiba-A_e923c6f749", "icon_YGOMD_First_Kaiba.png", 7},
		{"Stage 2-4", "OBB_NPC-MarikIshtar-A_6aebd9e87a", "icon_YGOMD_First_Marik.png", 8},
		{"Stage 2-5", "OBB_NPC-MokubaKaiba-A_fa0fe3e55a", "icon_YGOMD_First_Mokuba.png", 9}
	}};
}

inline std::array<Stage, 10> Load(std::string_view path) {
	auto result = Defaults();
	std::ifstream input{std::string(path)};
	if(!input) return result;
	try {
		nlohmann::json root;
		input >> root;
		if(root.value("schemaVersion", 0) != 1 || !root.at("stages").is_array()) return result;
		const auto& stages = root.at("stages");
		if(stages.size() != result.size()) return result;
		int previousUnlock = 0;
		for(size_t i = 0; i < result.size(); ++i) {
			const auto& stage = stages.at(i);
			if(stage.value("id", 0) != static_cast<int>(i + 1)
				|| !stage.contains("title") || !stage["title"].is_string()
				|| !stage.contains("deckKey") || !stage["deckKey"].is_string()
				|| !stage.contains("icon") || !stage["icon"].is_string()) return Defaults();
			const int unlock = stage.value("unlockAfterWins", -1);
			if(unlock < previousUnlock) return Defaults();
			result[i] = {stage.value("title", result[i].title), stage.value("deckKey", result[i].deckKey), stage.value("icon", result[i].icon), unlock};
			previousUnlock = unlock;
		}
	} catch(...) {
		return Defaults();
	}
	return result;
}

inline int LoadProgress(std::string_view path) {
	std::ifstream input{std::string(path)};
	if(!input) return 1;
	try {
		nlohmann::json root;
		input >> root;
		return std::clamp(root.value("unlocked", 1), 1, 10);
	} catch(...) {
		return 1;
	}
}

inline bool SaveProgress(std::string_view path, int unlocked) {
	std::ofstream output{std::string(path), std::ios::trunc};
	if(!output) return false;
	nlohmann::json root{{"schemaVersion", 1}, {"unlocked", std::clamp(unlocked, 1, 10)}};
	output << root.dump(2);
	return static_cast<bool>(output);
}
}
#endif
