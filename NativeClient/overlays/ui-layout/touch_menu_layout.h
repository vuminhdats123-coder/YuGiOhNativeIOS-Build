// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef EDOPRO_TOUCH_MENU_LAYOUT_H
#define EDOPRO_TOUCH_MENU_LAYOUT_H
#include <algorithm>

namespace ygo {
struct TouchMenuLayout {
    int x = 0, y = 0, width = 0, height = 0, rowHeight = 0, padding = 0;
    bool valid = false;
};

// Dimensions are renderer pixels after the caller applies EDOPro's DPI scale.
inline TouchMenuLayout FitTouchMenu(int viewportWidth, int viewportHeight, int anchorX, int anchorY,
                                   int preferredWidth, int preferredRowHeight, int margin, int rows) {
    if(rows < 1 || rows > 10 || viewportWidth < 3 || viewportHeight < rows + 2) return {};
    margin = std::clamp(margin, 0, std::min((viewportWidth - 3) / 2, (viewportHeight - rows - 2) / 2));
    const int availableWidth = viewportWidth - 2 * margin;
    const int availableHeight = viewportHeight - 2 * margin;
    const int padding = std::min(std::max(1, margin / 4),
                                 std::min((availableWidth - 1) / 2, (availableHeight - rows) / 2));
    const int width = std::clamp(preferredWidth, 2 * padding + 1, availableWidth);
    const int rowHeight = std::clamp(preferredRowHeight, 1, (availableHeight - 2 * padding) / rows);
    const int height = 2 * padding + rows * rowHeight;
    anchorX = std::clamp(anchorX, 0, viewportWidth);
    anchorY = std::clamp(anchorY, 0, viewportHeight);
    const int x = std::clamp(anchorX - width / 5, margin, viewportWidth - margin - width);
    const int aboveAnchor = std::max(0, anchorY - std::max(margin, rowHeight / 2));
    const int y = std::clamp(aboveAnchor - height,
                             margin, viewportHeight - margin - height);
    return {x, y, width, height, rowHeight, padding, true};
}
}
#endif
