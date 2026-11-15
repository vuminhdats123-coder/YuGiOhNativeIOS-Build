# iOS card-face compositor

This overlay draws a clean, legible card face from the existing artwork and
the active EDOPro database/locale. It is a styled native frame, not a claim to
reproduce Konami's printed card textures. It does not generate or download art.

Materialize only these files in `gframe/iOS/`:

- `card_face.h`
- `card_face_layout.h`
- `card_face.mm`

Compile `card_face.mm` for iOS with CoreGraphics, CoreText and ImageIO. The
portable headers contain no UIKit/Objective-C declarations. Minimum iOS remains
the project's existing iOS 16 target. The standalone native test main must not
be included in the application target.

## Data and threads

`ImageManager::SnapshotCardFace` copies name, description, type, attribute,
stats, scales and link markers while on the image-request/render thread. A
`shared_ptr<const CardFaceData>` belongs to each queued request. Worker threads
do not dereference the mutable DataManager or locale strings.

The compositor only creates a CPU bitmap and encodes PNG bytes in memory.
Irrlicht's existing image loader decodes those bytes as a CPU IImage. The
existing main/render-thread paths perform `addTexture`; no new GPU work is
issued from the background image loader. Metadata refresh requires
`imageManager.ClearTexture(false)` after changing locale. Stale jobs are dropped
using the cache epoch, rather than reintroducing old-language faces.

Covers and field images are unchanged. Already portrait-shaped card images
keep their original rendering. Square artwork (the supplied cards are mostly
238×238) is fitted without stretching into the portrait face. Missing artwork
uses the actual card metadata and a labeled empty artwork panel; missing card
metadata is explicitly labeled rather than fabricated.

## Layout

708×1016 preserves the client's 177:254 card ratio. The frame includes title,
attribute, level/rank stars, type line, description, ATK/DEF or Link rating, and
code. Fusion, Ritual, Synchro, Xyz, Pendulum, Link, Spell and Trap have distinct
styles; Link arrows use the database marker bits. Pendulum scales and separated
English effect/flavor sections are supported. The legacy Vietnamese source
often has no section labels; the renderer preserves that combined description
and directs the reader to the card-details panel, rather than guessing which
sentences are Pendulum effects.

Long text shrinks to a minimum size, then is explicitly ellipsized with a
full-text-in-details note. Tiny board thumbnails cannot replace the client's
full description panel. No metadata or artwork file is rewritten.

## Checks performed without build

```powershell
python NativeClient/overlays/card-renderer/verify_renderer_contract.py
```

The check reads the actual layout header, rejects region overlaps/out-of-bounds
coordinates, verifies queue ownership and worker access contracts statically,
and checks all 14,794 database rows and 7,714 JPG headers. It is not a native
compile, screenshot or visual quality test.

`tests/card_face_native_checks.mm` is authored for later Apple-platform checks:
PNG dimensions, artwork orientation, frame families, missing-art fallback,
Vietnamese text, long text and independent worker calls. It has **not run**.
Native compilation and device verification remain necessary before claiming
the compositor works end to end. No Xcode/GitHub Actions build was triggered.
