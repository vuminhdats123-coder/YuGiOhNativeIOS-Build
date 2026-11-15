// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef EDOPRO_DUEL_HUD_LAYOUT_H
#define EDOPRO_DUEL_HUD_LAYOUT_H
#include "duel_layout.h"
#include <string>

namespace ygo::duelui {
inline constexpr int ControlsMenuID = 30200, ControlsCloseID = 30201;
struct HudControls { Rect turn, menu; };
inline HudControls MakeHudControls(const Layout& layout) {
    const int gap = layout.selfHUD.top - layout.opponentHUD.bottom;
    if(!layout.valid || gap < 4 || layout.opponentHUD.Width() < 3) return {};
    const int pad = std::min(std::max(1, layout.opponentHUD.Width() / 24), std::max(1, gap / 8));
    const int height = std::min(std::max(1, layout.minimumTouchPixels), gap / 2);
    const int bottom = layout.selfHUD.top - pad;
    const int left = layout.opponentHUD.left + pad, right = layout.opponentHUD.right - pad;
    const Rect turn{left, layout.opponentHUD.bottom + pad, right, bottom - height - pad};
    if(turn.Width() <= 0 || turn.Height() <= 0) return {};
    return {turn, {left, bottom - height, right, bottom}};
}
struct HudPanel {
    Rect portrait, name, life, change, timer;
};
inline HudPanel MakeHudPanel(const Rect& panel, int minimumTextPixels = 0) {
    if(panel.Width() < 3 || panel.Height() < 3) return {};
    const int pad = std::max(1, std::min(panel.Width(), panel.Height()) / 24);
    const int left = panel.left + pad, right = std::max(left + 1, panel.right - pad);
    const int gap = std::max(1, panel.Height() / 100);
    const int line = std::max(1, minimumTextPixels > 0 ? minimumTextPixels : panel.Height() / 10);
    const int available = panel.Height() - 2 * pad;
    // Oversized custom text gets one exact-LP region rather than overlapping three unreadable lines.
    if(line > (available - 2 * gap) / 3)
        return {{}, {}, {left, panel.top + pad, right, panel.bottom - pad}, {}, {}};
    HudPanel result;
    int bottom = panel.bottom - pad;
    result.change = {left, bottom - line, right, bottom};
    bottom = result.change.top - gap;
    const int lifeHeight = std::max(line, int(std::lround(panel.Height() * 0.13)));
    const int life = std::min(lifeHeight, available - 2 * line - 2 * gap);
    result.life = {left, bottom - life, right, bottom};
    bottom = result.life.top - gap;
    const int timerHeight = std::max(1, panel.Height() / 50);
    if(bottom - timerHeight - gap - line >= panel.top + pad) {
        result.timer = {left, bottom - timerHeight, right, bottom};
        bottom = result.timer.top - gap;
    }
    result.name = {left, bottom - line, right, bottom};
    bottom = result.name.top - gap;
    const int portrait = std::max(0, std::min(right - left, bottom - (panel.top + pad)));
    const int imageLeft = left + ((right - left) - portrait) / 2;
    if(portrait > 0) result.portrait = {imageLeft, panel.top + pad, imageLeft + portrait, panel.top + pad + portrait};
    return result;
}
inline double LifeFraction(int life, int startingLife) {
    return startingLife > 0 ? std::clamp(double(life) / startingLife, 0.0, 1.0) : (life > 0 ? 1.0 : 0.0);
}
inline bool PortraitIconIsSafe(const std::string& icon) {
    return icon.size() > 4 && icon.size() <= 128 && icon.front() != '.'
        && icon.compare(icon.size() - 4, 4, ".png") == 0
        && icon.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-") == std::string::npos;
}
}
#endif
