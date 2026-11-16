// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef EDOPRO_CAMPAIGN_CATALOG_H
#define EDOPRO_CAMPAIGN_CATALOG_H

#include <array>
#include <fstream>
#include <string>
#include <string_view>
#include <nlohmann/json.hpp>

namespace ygo::campaignui {
struct Stage {
	std::string title;
	std::string icon;
	int unlockAfterWins = 0;
};

inline std::array<Stage, 10> Defaults() {
	return {{
		{"Stage 1-1", "icon_YGOMD_First_Weevil.png", 0},
		{"Stage 1-2", "icon_YGOMD_First_Kaiba.png", 1},
		{"Stage 1-3", "icon_YGOMD_First_Yugi.png", 2},
		{"Stage 1-4", "icon_YGOMD_First_Mai.png", 3},
		{"Stage 1-5", "icon_YGOMD_First_Pegasus.png", 4},
		{"Stage 2-1", "icon_YGOMD_GX_Jaden.png", 5},
		{"Stage 2-2", "icon_YGOMD_5DS_Yusei.png", 6},
		{"Stage 2-3", "icon_YGOMD_ZEXAL_Yuma.png", 7},
		{"Stage 2-4", "icon_YGOMD_Arcv_Yuya.png", 8},
		{"Stage 2-5", "icon_YGOMD_First_YamiYugi.png", 9}
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
				|| !stage.contains("icon") || !stage["icon"].is_string()) return Defaults();
			const int unlock = stage.value("unlockAfterWins", -1);
			if(unlock < previousUnlock) return Defaults();
			result[i] = {stage.value("title", result[i].title), stage.value("icon", result[i].icon), unlock};
			previousUnlock = unlock;
		}
	} catch(...) {
		return Defaults();
	}
	return result;
}
}
#endif
