// Exercises the production layout helper. Native execution is deferred while builds are held.
#include "../touch_menu_layout.h"
#include <cassert>
#include <limits>

int main() {
    using ygo::FitTouchMenu;
    const auto normal = FitTouchMenu(1024, 640, 500, 600, 156, 42, 6, 3);
    assert(normal.valid && normal.width == 156 && normal.rowHeight == 42);
    assert(normal.height == 2 * normal.padding + 3 * normal.rowHeight);
    for(auto width : {320, 568, 844, 1024, 2532}) {
        for(auto height : {240, 320, 390, 768, 1170}) {
            for(auto scale : {1, 2, 3}) {
                for(int rows = 1; rows <= 10; ++rows) {
                    for(auto x : {-100, 0, width / 2, width, width + 100}) {
                        for(auto y : {-100, 0, height / 2, height, height + 100}) {
                            const auto r = FitTouchMenu(width, height, x, y, 156 * scale, 42 * scale, 6 * scale, rows);
                            assert(r.valid && r.rowHeight > 0 && r.width > 2 * r.padding);
                            assert(r.x >= 0 && r.y >= 0 && r.x + r.width <= width && r.y + r.height <= height);
                            assert(r.height == 2 * r.padding + rows * r.rowHeight);
                            for(int row = 0; row < rows; ++row)
                                assert(r.padding + (row + 1) * r.rowHeight <= r.height - r.padding);
                        }
                    }
                }
            }
        }
    }
    assert(!FitTouchMenu(0, 640, 0, 0, 156, 42, 6, 2).valid);
    assert(!FitTouchMenu(640, 1, 0, 0, 156, 42, 6, 10).valid);
    assert(!FitTouchMenu(640, 480, 0, 0, 156, 42, 6, 0).valid);
    assert(!FitTouchMenu(640, 480, 0, 0, 156, 42, 6, 11).valid);
    const int limit = std::numeric_limits<int>::max();
    const auto large = FitTouchMenu(limit, limit, 0, 0, limit, limit, 0, 1);
    assert(large.valid && large.x >= 0 && large.y >= 0 && large.height <= limit);
}
