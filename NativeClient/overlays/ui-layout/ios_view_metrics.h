#ifndef EDOPRO_IOS_VIEW_METRICS_H
#define EDOPRO_IOS_VIEW_METRICS_H
#include <cstdint>

namespace porting {
struct IosViewMetrics {
    double left = 0, top = 0, right = 0, bottom = 0;
    double viewWidthPoints = 0, viewHeightPoints = 0;
    uint64_t revision = 0;
};
// UIKit publishes this snapshot on its main queue; game/render threads only read the copy.
IosViewMetrics getViewMetrics();
// Call on the GUI/render thread before its elements are destroyed or rebuilt.
void cancelNativeInput();
}
#endif
