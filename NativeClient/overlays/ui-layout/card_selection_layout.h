// SPDX-License-Identifier: AGPL-3.0-or-later
#ifndef EDOPRO_CARD_SELECTION_LAYOUT_H
#define EDOPRO_CARD_SELECTION_LAYOUT_H
#include "duel_layout.h"
#include <cstddef>
#include <limits>

namespace ygo::selectionui {
constexpr int Columns = 5, Rows = 3, VisibleSlots = Columns * Rows;
// Existing BUTTON_CARD_0/BUTTON_DISPLAY_0 ranges have only five IDs followed by unrelated controls.
constexpr int SelectID = 30100, DisplayID = 30120, CancelID = 30140;
inline int Slot(int id, int base) { return id >= base && id < base + VisibleSlots ? id - base : -1; }
inline int MaximumScrollRow(std::size_t count) {
    const auto rows = count / Columns + (count % Columns != 0);
    const auto maximum = rows > Rows ? rows - Rows : 0;
    return static_cast<int>(std::min(maximum, static_cast<std::size_t>(std::numeric_limits<int>::max() / Columns)));
}
inline std::size_t Offset(int scrollRow, std::size_t count) {
    return static_cast<std::size_t>(std::clamp(scrollRow, 0, MaximumScrollRow(count))) * Columns;
}
inline std::size_t Index(int slot, int scrollRow, std::size_t count) {
    if(slot < 0 || slot >= VisibleSlots) return count;
    const auto index = Offset(scrollRow, count) + static_cast<std::size_t>(slot);
    return index < count ? index : count;
}
struct Grid {
    duelui::Rect images[VisibleSlots], labels[VisibleSlots], scrollbar, status, confirm, cancel;
    int imageWidth = 0, imageHeight = 0;
    bool valid = false, touchTargetsCompressed = false;
};
inline Grid MakeGrid(int width, int height, int minimumTouchPixels, int captionHeight) {
    if(width < 64 || height < 96) return {};
    const double scale = std::min(width / 616.0, height / 600.0);
    const auto pixels = [scale](int logical) { return std::max(1, int(std::lround(logical * scale))); };
    const int padding = pixels(8), gap = pixels(6);
    const int top = std::min(std::max(pixels(32), std::clamp(captionHeight, 0, height / 4) + padding), height / 4);
    const int footer = std::min(std::max(pixels(48), std::max(1, minimumTouchPixels)), height / 4);
    const int scrollWidth = std::min(std::max(pixels(28), std::max(1, minimumTouchPixels)), width / 6);
    const int gridWidth = width - 2 * padding - scrollWidth - gap;
    const int gridHeight = height - top - footer - 2 * gap - padding;
    const int cellWidth = (gridWidth - (Columns - 1) * gap) / Columns;
    const int cellHeight = (gridHeight - (Rows - 1) * gap) / Rows;
    const int labelHeight = std::min(pixels(22), cellHeight / 3);
    if(cellWidth < 1 || cellHeight <= labelHeight + 1) return {};
    Grid grid;
    for(int slot = 0; slot < VisibleSlots; ++slot) {
        const int x = padding + (slot % Columns) * (cellWidth + gap);
        const int y = top + (slot / Columns) * (cellHeight + gap);
        grid.labels[slot] = {x, y, x + cellWidth, y + labelHeight};
        grid.images[slot] = {x, y + labelHeight + 1, x + cellWidth, y + cellHeight};
    }
    const int bottom = height - padding;
    const int confirmWidth = std::min(std::max(pixels(140), 2 * std::clamp(minimumTouchPixels, 1, width / 4)), width / 2);
    const int cancelWidth = std::min(std::max(pixels(110), std::max(1, minimumTouchPixels)), width / 3);
    grid.confirm = {width - padding - confirmWidth, bottom - footer, width - padding, bottom};
    grid.cancel = {padding, bottom - footer, padding + cancelWidth, bottom};
    grid.status = {grid.cancel.right + gap, bottom - footer, grid.confirm.left - gap, bottom};
    grid.scrollbar = {width - padding - scrollWidth, top, width - padding, top + gridHeight};
    grid.imageHeight = cellHeight - labelHeight - 1;
    grid.imageWidth = std::min(cellWidth, int(std::lround(grid.imageHeight * (177.0 / 254.0))));
    grid.imageWidth = std::max(1, grid.imageWidth);
    grid.imageHeight = std::max(1, std::min(grid.imageHeight, int(std::lround(grid.imageWidth * (254.0 / 177.0)))));
    grid.touchTargetsCompressed = cellWidth < minimumTouchPixels || cellHeight - labelHeight - 1 < minimumTouchPixels
                                 || footer < minimumTouchPixels || scrollWidth < minimumTouchPixels;
    grid.valid = true;
    return grid;
}
}
#endif
