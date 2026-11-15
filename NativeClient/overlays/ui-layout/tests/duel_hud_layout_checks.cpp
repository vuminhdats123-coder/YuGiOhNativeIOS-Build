// Native assertions against production geometry; authored, not compiled while builds are held.
#include "../duel_hud_layout.h"
#include <cassert>

int main() {
    using namespace ygo::duelui;
    for(const auto width : {568, 844, 1024, 2532}) for(const auto height : {320, 390, 640, 1170}) {
        const auto layout = MakeLayout(width, height, {0.03, 0, 0.03, 0.04});
        for(const auto panel : {layout.opponentHUD, layout.selfHUD}) {
            const auto hud = MakeHudPanel(panel);
            for(const auto r : {hud.portrait, hud.name, hud.life, hud.change, hud.timer}) {
                assert(r.left >= panel.left && r.top >= panel.top);
                assert(r.right <= panel.right && r.bottom <= panel.bottom);
                assert(r.Width() > 0 && r.Height() > 0);
            }
            assert(hud.portrait.Width() == hud.portrait.Height());
            assert(hud.portrait.bottom <= hud.name.top && hud.name.bottom <= hud.timer.top);
            assert(hud.timer.bottom <= hud.life.top && hud.life.bottom <= hud.change.top);
            for(const int textPixels : {8, 12, 16, 20, 32, 64, 256}) {
                const auto measured = MakeHudPanel(panel, textPixels);
                assert(measured.life.Width() > 0 && measured.life.Height() > 0);
                for(const auto region : {measured.portrait, measured.name, measured.life, measured.change, measured.timer}) {
                    if(region.Width() == 0 && region.Height() == 0) continue;
                    assert(region.left >= panel.left && region.top >= panel.top);
                    assert(region.right <= panel.right && region.bottom <= panel.bottom);
                }
                if(measured.name.Height() > 0) {
                    assert(measured.name.Height() >= textPixels && measured.life.Height() >= textPixels && measured.change.Height() >= textPixels);
                    assert(measured.name.bottom <= measured.life.top && measured.life.bottom <= measured.change.top);
                    if(measured.portrait.Height() > 0) assert(measured.portrait.bottom <= measured.name.top);
                    if(measured.timer.Height() > 0) assert(measured.name.bottom <= measured.timer.top && measured.timer.bottom <= measured.life.top);
                } else {
                    assert(measured.portrait.Height() == 0 && measured.change.Height() == 0 && measured.timer.Height() == 0);
                }
            }
        }
        const auto controls = MakeHudControls(layout);
        assert(controls.turn.Width() > 0 && controls.turn.Height() > 0);
        assert(controls.menu.Width() > 0 && controls.menu.Height() > 0);
        assert(controls.turn.left >= layout.opponentHUD.left && controls.turn.right <= layout.opponentHUD.right);
        assert(controls.turn.top > layout.opponentHUD.bottom && controls.turn.bottom < controls.menu.top);
        assert(controls.menu.bottom < layout.selfHUD.top);
        assert(controls.menu.Height() == std::min(layout.minimumTouchPixels, (layout.selfHUD.top - layout.opponentHUD.bottom) / 2));
    }
    assert(ControlsMenuID == 30200 && ControlsCloseID == 30201);
    assert(MakeHudControls({}).menu.Height() == 0);
    auto compressed = MakeLayout(568, 320);
    compressed.minimumTouchPixels = 1000;
    const auto controls = MakeHudControls(compressed);
    assert(controls.menu.Height() == (compressed.selfHUD.top - compressed.opponentHUD.bottom) / 2);
    assert(controls.turn.bottom < controls.menu.top);
    const Rect normalPanel{0, 0, 124, 212};
    assert(MakeHudPanel(normalPanel, 40).portrait.Height() < MakeHudPanel(normalPanel, 16).portrait.Height());
    const auto largeText = MakeHudPanel(normalPanel, 1000);
    assert(largeText.life.Height() > 190 && largeText.name.Height() == 0);
    assert(LifeFraction(4000, 8000) == 0.5);
    assert(LifeFraction(-100, 8000) == 0 && LifeFraction(12000, 8000) == 1);
    assert(LifeFraction(1, 0) == 1 && LifeFraction(0, 0) == 0);
    assert(PortraitIconIsSafe("icon_YGOMD_First_Tea.png"));
    assert(!PortraitIconIsSafe("../secret.png") && !PortraitIconIsSafe("C:/icon.png"));
    assert(!PortraitIconIsSafe("sub/icon.png") && !PortraitIconIsSafe("icon.jpg"));
}
