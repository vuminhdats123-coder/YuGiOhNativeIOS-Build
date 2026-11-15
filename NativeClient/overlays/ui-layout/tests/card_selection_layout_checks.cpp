// Exercises the production geometry/index helpers. Native compilation is deferred while builds are held.
#include "../card_selection_layout.h"
#include <cassert>
#include <set>

int main() {
    using namespace ygo::selectionui;
    static_assert(SelectID + VisibleSlots <= DisplayID);
    static_assert(DisplayID + VisibleSlots <= CancelID);
    assert(!MakeGrid(616, 600, 44, 24).touchTargetsCompressed);
    assert(MakeGrid(240, 240, 44, 24).touchTargetsCompressed);
    assert(Slot(SelectID + 14, SelectID) == 14 && Slot(SelectID + 15, SelectID) == -1);
    for(std::size_t count : {0u, 1u, 5u, 6u, 14u, 15u, 16u, 19u, 20u, 61u, 4096u}) {
        std::set<std::size_t> reachable;
        for(int row = 0; row <= MaximumScrollRow(count); ++row)
            for(int slot = 0; slot < VisibleSlots; ++slot) {
                const auto index = Index(slot, row, count);
                assert(index == count || index == static_cast<std::size_t>(row * Columns + slot));
                if(index < count) reachable.insert(index);
            }
        assert(reachable.size() == count);
        assert(Index(-1, 0, count) == count && Index(VisibleSlots, 0, count) == count);
        assert(Offset(-100, count) == 0);
    }
    for(int width : {240, 360, 616, 1080, 1848}) for(int height : {240, 400, 600, 1080, 1800}) {
        const auto grid = MakeGrid(width, height, 44, 24);
        assert(grid.valid);
        auto inside = [=](const ygo::duelui::Rect& rect) {
            return rect.left >= 0 && rect.top >= 0 && rect.Width() > 0 && rect.Height() > 0
                   && rect.right <= width && rect.bottom <= height;
        };
        assert(inside(grid.scrollbar) && inside(grid.status) && inside(grid.confirm) && inside(grid.cancel));
        assert(grid.cancel.right < grid.status.left && grid.status.right < grid.confirm.left);
        for(int slot = 0; slot < VisibleSlots; ++slot) {
            assert(inside(grid.images[slot]) && inside(grid.labels[slot]));
            assert(grid.images[slot].bottom < grid.confirm.top);
            assert(grid.images[slot].right < grid.scrollbar.left);
        }
    }
    assert(!MakeGrid(0, 600, 44, 24).valid);
    assert(!MakeGrid(600, 0, 44, 24).valid);
}
