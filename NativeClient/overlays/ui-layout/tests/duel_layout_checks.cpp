// Production layout/projection checks; authored only while native builds are on hold.
#include "../duel_layout.h"
#include <cassert>
#include <cmath>

int main() {
    using namespace ygo::duelui;
    for(const auto width : {568, 844, 1024, 2532}) for(const auto height : {320, 390, 768, 1170}) {
        for(const auto insets : {Insets{}, Insets{0.06, 0, 0.06, 0.06}}) {
            auto layout = MakeLayout(width, height, insets, height / 3.0);
            assert(layout.valid);
            for(const auto rect : {layout.preview, layout.info, layout.board, layout.opponentHUD, layout.selfHUD, layout.selection, layout.phase}) {
                assert(rect.Width() > 0 && rect.Height() > 0);
                assert(rect.left >= layout.content.left && rect.right <= layout.content.right);
                assert(rect.top >= layout.content.top && rect.bottom <= layout.content.bottom);
            }
            assert(layout.preview.right < layout.board.left && layout.board.right < layout.opponentHUD.left);
            assert(layout.board.bottom < layout.phase.top);
            auto projection = BoardProjection(layout, width, height);
            assert(projection.valid && projection.nearWidth >= 10.4 / (7.8 * 1.4) - 1e-10);
            // Pinned ClientField top-down hands: Y=+/-2.5, Z=3+/-0.001*sequence;
            // hover moves Y inward by .2. Test every card corner, not only world Z=0.
            for(int count : {1, 5, 6, 40, 60, 120}) for(int player : {0, 1}) {
                for(int sequence = 0; sequence < count; ++sequence) for(int hovered : {0, 1}) {
                    double x;
                    if(count <= 5) {
                        const double offset = (5.5 - 0.8 * count) / 2 + sequence * 0.73;
                        x = player == 0 ? 1.55 + offset : 6.25 - offset;
                    } else {
                        const double offset = sequence * 3.65 / (count - 1);
                        x = player == 0 ? 1.9 + offset : 5.9 - offset;
                    }
                    x += player == 0 ? 0.3 : 0.3 - 0.378;
                    const double y = (player == 0 ? 1 : -1) * (2.5 - hovered * 0.2);
                    const double z = 3 + (player == 0 ? 1 : -1) * sequence * 0.001;
                    for(double dx : {-0.35, 0.35}) for(double dy : {-0.5, 0.5}) {
                        const double clipX = (x + dx - 4.2) * 2 / (projection.nearWidth * (7.8 * 1.4 - z));
                        const double clipY = -(y + dy) * 2 / (projection.nearHeight * (7.8 * 1.4 - z));
                        assert(std::abs(clipX) <= 1 && std::abs(clipY) <= 1);
                    }
                }
            }
            for(double x : {-1.0, 0.0, 1.0}) for(double y : {-1.0, 0.0, 1.0}) {
                const double screenX = (x * projection.scaleX + projection.offsetX + 1) * width / 2;
                const double screenY = (1 - y * projection.scaleY - projection.offsetY) * height / 2;
                const double inverseX = (2 * screenX / width - 1 - projection.offsetX) / projection.scaleX;
                const double inverseY = (1 - 2 * screenY / height - projection.offsetY) / projection.scaleY;
                assert(std::abs(inverseX - x) < 1e-10 && std::abs(inverseY - y) < 1e-10);
            }
        }
    }
    auto phone = MakeLayout(2532, 1170, {47.0/844, 0, 47.0/844, 21.0/390}, 390);
    assert(phone.minimumTouchPixels == 132 && !phone.touchTargetsCompressed);
    assert(!phone.board.Contains(phone.opponentHUD.left, phone.opponentHUD.top));
    assert(!MakeLayout(0, 0).valid);
}
