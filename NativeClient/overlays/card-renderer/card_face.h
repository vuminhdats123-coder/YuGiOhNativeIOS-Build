#ifndef EDOPRO_IOS_CARD_FACE_H
#define EDOPRO_IOS_CARD_FACE_H

#include <cstdint>
#include <string>
#include <vector>

namespace ygo {
// Values and localized strings are copied before a request enters the image worker queue.
struct CardFaceData {
    uint32_t code = 0, type = 0, attribute = 0, level = 0;
    uint32_t leftScale = 0, rightScale = 0, linkMarkers = 0;
    int32_t attack = -2, defense = -2;
    std::string name, description, typeLine, attributeText;
    bool known = false;
};

// CPU-only, no UIKit views, mutable database access, filesystem writes, or GPU calls.
// Artwork is optional RGBA8, row-major from the top left; an empty vector draws a labeled placeholder.
std::vector<uint8_t> RenderIOSCardFace(const CardFaceData& card, const std::vector<uint8_t>& artwork,
                                     uint32_t artworkWidth, uint32_t artworkHeight);
}
#endif
