#ifndef EDOPRO_IOS_CARD_FACE_LAYOUT_H
#define EDOPRO_IOS_CARD_FACE_LAYOUT_H

namespace ygo::cardface {
struct Rect { double x, y, width, height; };
constexpr double Width = 708;
constexpr double Height = 1016;
constexpr Rect Title = {36, 30, 558, 58};
constexpr Rect Attribute = {612, 30, 64, 64};
constexpr Rect Level = {44, 100, 620, 32};
constexpr Rect Art = {70, 142, 568, 568};
constexpr Rect LinkArt = {90, 156, 528, 528};
constexpr Rect PendulumArt = {70, 142, 568, 432};
constexpr Rect PendulumText = {108, 596, 492, 118};
constexpr Rect LeftScale = {40, 616, 56, 70};
constexpr Rect RightScale = {612, 616, 56, 70};
constexpr Rect TypeLine = {44, 728, 620, 36};
constexpr Rect Description = {44, 774, 620, 162};
constexpr Rect Statistics = {44, 944, 620, 32};
constexpr Rect Footer = {44, 984, 620, 20};
}
#endif
