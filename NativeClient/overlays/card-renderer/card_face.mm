#include "card_face.h"
#include "card_face_layout.h"
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
#include <ImageIO/ImageIO.h>
#include <algorithm>
#include <cmath>

namespace ygo {
namespace {
constexpr uint32_t Monster = 0x1, Spell = 0x2, Trap = 0x4, Normal = 0x10;
constexpr uint32_t Fusion = 0x40, Ritual = 0x80, Synchro = 0x2000;
constexpr uint32_t Xyz = 0x800000, Pendulum = 0x1000000, Link = 0x4000000;
constexpr double Pi = 3.14159265358979323846;
using cardface::Rect;

CGRect box(Rect r) { return CGRectMake(r.x, cardface::Height - r.y - r.height, r.width, r.height); }
void color(CGContextRef context, double r, double g, double b) { CGContextSetRGBFillColor(context, r, g, b, 1); }
void fill(CGContextRef context, Rect r, double red, double green, double blue) {
    color(context, red, green, blue); CGContextFillRect(context, box(r));
}

CFStringRef string(const std::string& text) {
    auto value = CFStringCreateWithBytes(kCFAllocatorDefault, reinterpret_cast<const UInt8*>(text.data()),
                                       static_cast<CFIndex>(text.size()), kCFStringEncodingUTF8, false);
    return value ? value : CFStringCreateCopy(kCFAllocatorDefault, CFSTR("Invalid text"));
}

// Returns false if the text had to be visibly ellipsized at the minimum readable size.
bool drawText(CGContextRef context, const std::string& value, Rect rect, double size, double minimum,
              bool bold = false, bool white = false, bool centered = false) {
    if(value.empty()) return true;
    CFStringRef text = string(value);
    CGColorRef foreground = CGColorCreateGenericRGB(white ? 1 : 0.08, white ? 1 : 0.08, white ? 1 : 0.08, 1);
    auto alignment = centered ? kCTTextAlignmentCenter : kCTTextAlignmentLeft;
    CTLineBreakMode lineBreak = kCTLineBreakByWordWrapping;
    CTParagraphStyleSetting settings[] = {
        {kCTParagraphStyleSpecifierAlignment, sizeof(alignment), &alignment},
        {kCTParagraphStyleSpecifierLineBreakMode, sizeof(lineBreak), &lineBreak}
    };
    CTParagraphStyleRef paragraph = CTParagraphStyleCreate(settings, 2);
    CGPathRef path = CGPathCreateWithRect(box(rect), nullptr);
    bool complete = false;
    for(double fontSize = size; fontSize >= minimum; fontSize -= 1) {
        CTFontRef font = CTFontCreateWithName(bold ? CFSTR("HelveticaNeue-Bold") : CFSTR("HelveticaNeue"), fontSize, nullptr);
        const void* keys[] = {kCTFontAttributeName, kCTForegroundColorAttributeName, kCTParagraphStyleAttributeName};
        const void* vals[] = {font, foreground, paragraph};
        CFDictionaryRef attrs = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 3,
                                                   &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFAttributedStringRef attributed = CFAttributedStringCreate(kCFAllocatorDefault, text, attrs);
        CTFramesetterRef setter = CTFramesetterCreateWithAttributedString(attributed);
        CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, nullptr);
        CFRange visible = CTFrameGetVisibleStringRange(frame);
        complete = visible.length >= CFStringGetLength(text);
        if(complete || fontSize == minimum) {
            if(!complete) {
                CFMutableStringRef truncated = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, text);
                CFIndex keep = std::max<CFIndex>(0, visible.length - 4);
                // Avoid splitting a UTF-16 surrogate pair in localized text.
                if(keep > 0 && CFStringGetCharacterAtIndex(truncated, keep - 1) >= 0xD800
                            && CFStringGetCharacterAtIndex(truncated, keep - 1) <= 0xDBFF) --keep;
                CFStringDelete(truncated, CFRangeMake(keep, CFStringGetLength(truncated) - keep));
                CFStringAppend(truncated, CFSTR("…"));
                CFRelease(frame); CFRelease(setter); CFRelease(attributed);
                attributed = CFAttributedStringCreate(kCFAllocatorDefault, truncated, attrs);
                setter = CTFramesetterCreateWithAttributedString(attributed);
                frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, nullptr);
                CFRelease(truncated);
            }
            CGContextSetTextMatrix(context, CGAffineTransformIdentity);
            CTFrameDraw(frame, context);
        }
        CFRelease(frame); CFRelease(setter); CFRelease(attributed); CFRelease(attrs); CFRelease(font);
        if(complete || fontSize == minimum) break;
    }
    CGPathRelease(path); CFRelease(paragraph); CGColorRelease(foreground); CFRelease(text);
    return complete;
}

void star(CGContextRef context, double x, double y, double radius) {
    CGContextBeginPath(context);
    for(int point = 0; point < 10; ++point) {
        const double angle = -Pi / 2 + point * Pi / 5;
        const double r = point % 2 == 0 ? radius : radius * 0.43;
        const double px = x + std::cos(angle) * r;
        const double py = cardface::Height - (y + std::sin(angle) * r);
        if(point == 0) CGContextMoveToPoint(context, px, py);
        else CGContextAddLineToPoint(context, px, py);
    }
    CGContextClosePath(context); CGContextFillPath(context);
}

void frameColor(CGContextRef context, uint32_t type) {
    if(type & Spell) color(context, 0.20, 0.57, 0.48);
    else if(type & Trap) color(context, 0.68, 0.35, 0.53);
    else if(type & Link) color(context, 0.17, 0.37, 0.65);
    else if(type & Xyz) color(context, 0.16, 0.17, 0.20);
    else if(type & Synchro) color(context, 0.87, 0.89, 0.90);
    else if(type & Fusion) color(context, 0.55, 0.39, 0.69);
    else if(type & Ritual) color(context, 0.35, 0.55, 0.73);
    else if(type & Normal) color(context, 0.82, 0.67, 0.39);
    else color(context, 0.75, 0.48, 0.27);
}

std::string number(int32_t value) { return value < 0 ? "?" : std::to_string(value); }

void drawArtwork(CGContextRef context, const std::vector<uint8_t>& bytes, uint32_t width, uint32_t height, Rect area) {
    fill(context, area, 0.12, 0.14, 0.17);
    if(width == 0 || height == 0 || width > 4096 || height > 4096 || bytes.size() != static_cast<size_t>(width) * height * 4) {
        drawText(context, "Artwork unavailable", {area.x + 20, area.y + area.height / 2 - 20, area.width - 40, 80}, 28, 22, true, true, true);
        return;
    }
    CGDataProviderRef provider = CGDataProviderCreateWithData(nullptr, bytes.data(), bytes.size(), nullptr);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(width, height, 8, 32, width * 4, space,
                                    static_cast<CGBitmapInfo>(kCGBitmapByteOrder32Big | kCGImageAlphaLast), provider, nullptr, false, kCGRenderingIntentDefault);
    if(image) {
        const double scale = std::min(area.width / width, area.height / height);
        Rect fitted{area.x + (area.width - width * scale) / 2, area.y + (area.height - height * scale) / 2,
                    width * scale, height * scale};
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        CGContextDrawImage(context, box(fitted), image);
        CGImageRelease(image);
    } else {
        drawText(context, "Artwork unavailable", {area.x + 20, area.y + area.height / 2 - 20, area.width - 40, 80}, 28, 22, true, true, true);
    }
    CGColorSpaceRelease(space); CGDataProviderRelease(provider);
}

void linkArrows(CGContextRef context, uint32_t markers, Rect art) {
    struct Arrow { uint32_t bit; double dx, dy; };
    const Arrow arrows[] = {{0x40,-1,-1},{0x80,0,-1},{0x100,1,-1},{0x8,-1,0},
                            {0x20,1,0},{0x1,-1,1},{0x2,0,1},{0x4,1,1}};
    for(const auto& arrow : arrows) {
        if(!(markers & arrow.bit)) continue;
        double x = art.x + art.width / 2 + arrow.dx * (art.width / 2 + 17);
        double y = art.y + art.height / 2 + arrow.dy * (art.height / 2 + 17);
        double angle = std::atan2(arrow.dy, arrow.dx);
        color(context, 1, 0.48, 0.12); CGContextBeginPath(context);
        for(int i = 0; i < 3; ++i) {
            double a = angle + i * 2 * Pi / 3;
            double px = x + 14 * std::cos(a), py = cardface::Height - (y + 14 * std::sin(a));
            if(i == 0) CGContextMoveToPoint(context, px, py); else CGContextAddLineToPoint(context, px, py);
        }
        CGContextClosePath(context); CGContextFillPath(context);
    }
}

void splitPendulum(const std::string& text, bool normal, std::string& pendulum, std::string& monster) {
    const std::string pendulumTag = "[ Pendulum Effect ]";
    std::string monsterTag = "[ Monster Effect ]";
    auto separator = text.find("----------------------------------------");
    auto first = text.find(pendulumTag), second = text.find(monsterTag);
    if(second == std::string::npos) { monsterTag = "[ Flavor Text ]"; second = text.find(monsterTag); }
    if(first != std::string::npos && second != std::string::npos && second > first) {
        pendulum = text.substr(first + pendulumTag.size(), (separator != std::string::npos && separator > first ? separator : second) - first - pendulumTag.size());
        monster = text.substr(second + monsterTag.size());
    } else {
        // shortcut: legacy localized text may not have these headings; keep all text in the main box until locale-specific separators are defined.
        monster = text; pendulum = normal ? "" : "Effect text: see card details";
    }
}
}

std::vector<uint8_t> RenderIOSCardFace(const CardFaceData& card, const std::vector<uint8_t>& artwork,
                                     uint32_t artworkWidth, uint32_t artworkHeight) {
    const size_t width = static_cast<size_t>(cardface::Width), height = static_cast<size_t>(cardface::Height);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(nullptr, width, height, 8, width * 4, space,
                                                static_cast<CGBitmapInfo>(kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast));
    CGColorSpaceRelease(space);
    if(!context) return {};
    fill(context, {0,0,cardface::Width,cardface::Height}, 0.12, 0.13, 0.15);
    frameColor(context, card.type); CGContextFillRect(context, box({14,14,680,988}));
    if(card.type & Pendulum) fill(context, {20,582,668,414}, 0.25, 0.60, 0.49);
    fill(context, cardface::Title, 0.96, 0.93, 0.82);
    bool complete = drawText(context, card.name, cardface::Title, 34, 20, true);
    fill(context, cardface::Attribute, 0.16, 0.18, 0.23);
    drawText(context, card.attributeText, {612,48,64,44}, 14, 10, true, true, true);
    fill(context, cardface::Level, 0.16, 0.18, 0.23);
    std::string level;
    if(card.type & Monster) {
        level = (card.type & Link) ? "LINK " : (card.type & Xyz) ? "RANK " : "LEVEL ";
        level += card.level <= 13 ? std::to_string(card.level) : "?";
        if(!(card.type & Link) && card.level <= 13) {
            color(context, 1, 0.83, 0.22);
            for(uint32_t i = 0; i < card.level; ++i) star(context, 56 + i * 30, 116, 12);
        }
        drawText(context, level, {488,103,176,32}, 20, 15, true, true);
    } else drawText(context, card.typeLine, cardface::Level, 22, 16, true, true);
    const Rect art = (card.type & Pendulum) ? cardface::PendulumArt : (card.type & Link) ? cardface::LinkArt : cardface::Art;
    drawArtwork(context, artwork, artworkWidth, artworkHeight, art);
    if(card.type & Link) linkArrows(context, card.linkMarkers, art);
    std::string description = card.description;
    if(card.type & Pendulum) {
        std::string pendulum;
        splitPendulum(card.description, card.type & Normal, pendulum, description);
        fill(context, cardface::PendulumText, 0.95, 0.97, 0.90);
        complete = drawText(context, pendulum, cardface::PendulumText, 20, 14) && complete;
        drawText(context, std::to_string(card.leftScale), cardface::LeftScale, 42, 28, true, false, true);
        drawText(context, std::to_string(card.rightScale), cardface::RightScale, 42, 28, true, false, true);
    }
    fill(context, {34,720,640,260}, 0.97, 0.95, 0.87);
    complete = drawText(context, card.typeLine, cardface::TypeLine, 23, 16, true) && complete;
    complete = drawText(context, description, cardface::Description, 22, 14) && complete;
    if(card.type & Monster) {
        std::string stats = "ATK/" + number(card.attack);
        stats += (card.type & Link) ? "   LINK-" + std::to_string(card.level) : "   DEF/" + number(card.defense);
        drawText(context, stats, cardface::Statistics, 25, 20, true);
    }
    const std::string footer = "Code " + std::to_string(card.code) + (complete ? "" : "  |  Full text in card details");
    fill(context, cardface::Footer, 0.16, 0.18, 0.23);
    drawText(context, footer, cardface::Footer, 15, 12, false, true);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if(!image) return {};
    CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
    if(!data) { CGImageRelease(image); return {}; }
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(data, CFSTR("public.png"), 1, nullptr);
    bool saved = false;
    if(destination) { CGImageDestinationAddImage(destination, image, nullptr); saved = CGImageDestinationFinalize(destination); CFRelease(destination); }
    CGImageRelease(image);
    std::vector<uint8_t> bytes;
    if(saved) bytes.assign(CFDataGetBytePtr(data), CFDataGetBytePtr(data) + CFDataGetLength(data));
    CFRelease(data);
    return bytes;
}
}
