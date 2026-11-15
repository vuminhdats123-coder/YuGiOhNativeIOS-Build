// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef EDOPRO_DUEL_LAYOUT_H
#define EDOPRO_DUEL_LAYOUT_H
#include <algorithm>
#include <cmath>

namespace ygo::duelui {
struct Insets { double left = 0, top = 0, right = 0, bottom = 0; };
struct Rect {
    int left = 0, top = 0, right = 0, bottom = 0;
    int Width() const { return right - left; }
    int Height() const { return bottom - top; }
    bool Contains(int x, int y) const { return x >= left && x < right && y >= top && y < bottom; }
};
struct Layout {
    Rect content, preview, info, board, opponentHUD, selfHUD, selection, phase;
    int minimumTouchPixels = 1;
    bool valid = false, touchTargetsCompressed = false;
};

inline Layout MakeLayout(int width, int height, Insets insets = {}, double viewHeightPoints = 0) {
    if(width < 64 || height < 64) return {};
    const auto fraction = [](double value) { return std::isfinite(value) ? std::clamp(value, 0.0, 0.45) : 0.0; };
    Layout result;
    result.content = {int(std::ceil(width * fraction(insets.left))), int(std::ceil(height * fraction(insets.top))),
                      width - int(std::ceil(width * fraction(insets.right))), height - int(std::ceil(height * fraction(insets.bottom)))};
    const auto& content = result.content;
    if(content.Width() < 64 || content.Height() < 64) return result;
    const auto map = [&](int x1, int y1, int x2, int y2) {
        return Rect{content.left + int(std::lround(content.Width() * (x1 / 1024.0))),
                    content.top + int(std::lround(content.Height() * (y1 / 640.0))),
                    content.left + int(std::lround(content.Width() * (x2 / 1024.0))),
                    content.top + int(std::lround(content.Height() * (y2 / 640.0)))};
    };
    // shortcut: use scaled targets until UIKit's first point-dimension snapshot arrives.
    result.minimumTouchPixels = std::max(1, int(std::ceil(std::isfinite(viewHeightPoints) && viewHeightPoints > 0
        ? std::min(double(height), 44.0 * height / viewHeightPoints) : content.Height() * (40.0 / 640.0))));
    result.preview = map(8, 8, 244, 258);
    result.info = map(8, 266, 244, 632);
    result.board = map(252, 8, 884, 584);
    result.opponentHUD = map(892, 8, 1016, 220);
    result.selfHUD = map(892, 420, 1016, 632);
    result.selection = map(260, 20, 876, 620);
    result.phase = map(252, 592, 884, 632);
    const int phaseHeight = std::min(std::max(result.phase.Height(), result.minimumTouchPixels), content.Height() / 5);
    result.phase.top = result.phase.bottom - phaseHeight;
    // MR5 Extra Monster Zones occupy the center; the phase bar stays below the hands instead.
    result.board.bottom = result.phase.top - std::max(2, int(std::lround(content.Height() * (8.0 / 640.0))));
    result.touchTargetsCompressed = phaseHeight < result.minimumTouchPixels || result.phase.Width() / 7 < result.minimumTouchPixels;
    result.valid = result.board.Width() > 0 && result.board.Height() > 0;
    return result;
}

struct Projection {
    double nearWidth = 0, nearHeight = 0, scaleX = 0, scaleY = 0, offsetX = 0, offsetY = 0;
    bool valid = false;
};
inline Projection BoardProjection(const Layout& layout, int width, int height) {
    if(!layout.valid || width <= 0 || height <= 0) return {};
    const auto& board = layout.board;
    const double aspect = double(board.Width()) / board.Height();
    // The existing top-down camera is at Z=7.8*1.4. Keep its perspective hand elevation,
    // while fitting world X=-1..9 around FIELD_X=4.2 into the central board region.
    const double nearHeight = std::max(0.84, (10.4 / (7.8 * 1.4)) / aspect);
    return {nearHeight * aspect, nearHeight, double(board.Width()) / width, double(board.Height()) / height,
            (double(board.left) + board.right) / width - 1.0, 1.0 - (double(board.top) + board.bottom) / height, true};
}
}
#endif
