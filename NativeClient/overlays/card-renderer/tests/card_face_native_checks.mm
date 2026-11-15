// Standalone Apple-platform checks. Authored only: do not add this main() to the application target.
#include "../card_face.h"
#include "../card_face_layout.h"
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <cassert>
#include <thread>

static std::vector<uint8_t> pixels(const std::vector<uint8_t>& png) {
    assert(png.size() > 8 && png[0] == 137 && png[1] == 'P');
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, png.data(), static_cast<CFIndex>(png.size()));
    CGImageSourceRef source = CGImageSourceCreateWithData(data, nullptr);
    assert(source);
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
    assert(image && CGImageGetWidth(image) == 708 && CGImageGetHeight(image) == 1016);
    std::vector<uint8_t> rgba(708 * 1016 * 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rgba.data(), 708, 1016, 8, 708 * 4, space,
        static_cast<CGBitmapInfo>(kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast));
    assert(context);
    CGContextDrawImage(context, CGRectMake(0, 0, 708, 1016), image);
    CGContextRelease(context); CGColorSpaceRelease(space); CGImageRelease(image); CFRelease(source); CFRelease(data);
    return rgba;
}

int main() {
    ygo::CardFaceData card;
    card.code = 89631139; card.type = 0x11; card.known = true;
    card.level = 8; card.attack = 3000; card.defense = 2500;
    card.name = "Blue-Eyes White Dragon"; card.attributeText = "LIGHT";
    card.typeLine = "Dragon / Normal"; card.description = "Con rồng huyền thoại: kiểm tra dấu tiếng Việt.";
    const std::vector<uint8_t> art = {
        255,0,0,255, 255,0,0,255,
        0,0,255,255, 0,0,255,255
    };
    auto face = pixels(ygo::RenderIOSCardFace(card, art, 2, 2));
    auto offset = [](int x, int y) { return (y * 708 + x) * 4; };
    // Verify that source top/bottom rows remain upright inside the artwork rectangle.
    assert(face[offset(350, 200)] > 220 && face[offset(350, 200) + 2] < 30);
    assert(face[offset(350, 650) + 2] > 220 && face[offset(350, 650)] < 30);
    for(uint32_t type : {0x2u, 0x4u, 0x41u, 0x81u, 0x2001u, 0x800021u, 0x1000021u, 0x4000021u}) {
        card.type = type; card.linkMarkers = 0x1EF; card.leftScale = 1; card.rightScale = 8;
        card.description = "[ Pendulum Effect ]\nA pendulum effect.\n----------------------------------------\n[ Monster Effect ]\nA monster effect.";
        assert(!pixels(ygo::RenderIOSCardFace(card, {}, 0, 0)).empty());
    }
    card.name.assign(1000, 'W'); card.description.assign(8000, 'X');
    assert(!pixels(ygo::RenderIOSCardFace(card, {}, 0, 0)).empty());
    // Each compositor call owns its drawing context; no shared graphics/database state.
    std::thread first([card] { assert(!ygo::RenderIOSCardFace(card, {}, 0, 0).empty()); });
    std::thread second([card] { assert(!ygo::RenderIOSCardFace(card, {}, 0, 0).empty()); });
    first.join(); second.join();
}
