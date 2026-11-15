# Native iOS source configuration

The app target is `ygopro`, linked to the pinned `ocgcore`, `lua`, and `clzma`
static source targets. The Lua customization header is forced with an explicit
Xcode GCC_PREFIX_HEADER (precompilation disabled), because the pinned exporter
does not emit the upstream forceincludes setting. All iOS .mm files have explicit
Objective-C++ types. The upstream optional `ocgcoreshared` project remains
available, but is not a dependency of the iOS app. `ygoprodll` is not generated
for iOS. Lua `.c` sources retain upstream C++ compilation and explicitly enable
C++ exceptions for the core's stack-unwinding contract.

`overlays/ios-config/native_config.lua` is materialized as
`edopro/gframe/iOS/native_config.lua`. It sets iOS 16, arm64, iPhone/iPad landscape,
static core linkage and disabled code signing. CoreGraphics, CoreText, ImageIO
and JavaScriptCore are linked alongside UIKit, Foundation and OpenGLES.
All Objective-C sources keep manual reference counting, with balanced ownership
for the modern text/picker handlers in `porting_ios.mm`. Each native dialog keeps
one generation token and its originating widget; queued results are applied
only while that widget is live, focused and unchanged. Cancel and Game teardown
invalidate pending results and release the retained widget before its environment.
At the pinned Irrlicht revision, `runIrrlicht` enters `irrlicht_main` on the UIKit
main thread and the device loop pumps CFRunLoop; GUI/render callbacks share that
thread, while duel/asset workers remain separate. Irrlicht's UIApplicationDelegate
forwards pause/resume to the client's Suspend/Resume. The first resumed frame
resets local animation elapsed time, except during a live network duel so its
countdown retains the existing behavior. No scene manifest replaces this path.

The Info.plist uses Xcode product/version substitutions and iOS's `UILaunchScreen`
dictionary. It does not reference the upstream missing LaunchScreen storyboard,
old signing data, SDK build identifiers, or compiled Assets.car. App icons are
the 17 original PNG variants, copied by an explicit allowlist.

## Inputs already prepared, without compilation

The original official dependency archive is stored at
`outputs/ios-dependencies/installed_aarch64-ios-cctools-20260914.7z`; its SHA256 is
locked in `dependencies.lock.json`. It was extracted into a fresh
`outputs/ios-dependencies/vcpkg-20260914` directory. The 935 extracted files
include both release/debug libraries, headers, and upstream copyright files.

`audit_dependencies.py` parses ar and Mach-O bytes without loading any binary.
All 50 static libraries contain arm64 iPhoneOS objects (4,468 objects total),
built with SDK 16.1 and minimum iOS 7. This verifies architecture/platform,
not successful linking against a later Xcode or behavior on an iPhone. Detailed
hashes and member counts are in `outputs/ios-dependencies/macho-audit.json`.
The exact cache source and its Irrlicht source pin are in the lock file.

The prepared game directory must include `offline-ai/offline_ai.js`,
`config/duel-portraits.json`, `textures/portraits/player.png`, all card
data, pictures, scripts, textures, fonts, audio and `package-manifest.json`.
Supply it explicitly with `--ios-game-data`; do not point at an older payload
without the current overlays. Payload generation and application compilation
are separate operations.

## Xcode project recipe (source only; no compiler required to generate)

After materializing the patch series, run Premake **from `NativeClient/edopro`**
with these arguments. Use absolute paths appropriate to the machine running
Premake; a generated project with Windows absolute paths is only a structural
check, not a portable Mac project.

```text
premake5 --os=ios --architecture=arm64 --vcpkg-root=<verified-vcpkg-root> --sound=miniaudio --no-joystick=true --ios-game-data=<prepared-game-directory> xcode4
```

Optional inputs: `--ios-bundle-id=com.vuminhdats.YuGiOhNativeIOS` and
`--ios-python=/usr/bin/python3`. The default Python must be available in Xcode's
build environment. This recipe rejects dynamic/prebuilt core overrides,
simulator archives, missing static release libraries, and a missing AI payload.
Native compilation, signing, packaging into IPA, and GitHub Actions remain
separate later steps; this configuration does not trigger any of them.

## Directory-preserving resources

The Xcode post-build resource phase invokes the materialized
`gframe/iOS/copy_bundle_resources.py`. It verifies every file's manifest size and
SHA256 while copying to a fresh staging directory inside the `.app`, then installs
the complete tree at `App.app/game`. It never adds 46,000 individual Xcode
resource entries that might flatten card/script directory structure. It rejects
extra files, traversal, normalized path aliases, case collisions, symlinks, a
non-app destination, and an existing unrecognized game directory. A failed copy
keeps an existing valid game payload untouched. Only the controlled staging
directory and an old managed `game` copy may be removed.

At runtime the existing bootstrap copies `Bundle/game` to `Documents/EDOPro`
on first launch. An identical manifest reuses the user's writable installation.
A different manifest is deliberately refused; decks, replays and settings are
not overwritten. Automatic installed-data migration is still unsupported and
must be designed before shipping a later native data revision. Bootstrap errors
also work with Irrlicht's legacy window setup, including before its window exists.

## Checks

`python -m unittest discover -s tests -p test_native_ios_resources.py -v`
uses small resource/Mach-O fixtures only. No generator, native compiler, Lua
runtime, simulator or code-signing tool is run by those checks. The symlink
fixture is skipped on Windows hosts without permission to create symlinks.
Native UI/input, graphics, audio, JSCore bridging and runtime resource lookup
remain unverified until an authorized native build and device run.

The new duel layout reads UIKit safe-area/point dimensions on the main queue and
publishes normalized snapshots to the render loop. Board projection, hit-testing,
right-side HUD, card-info panel and the 5-by-3 selection grid use shared geometry.
Native assertions in `overlays/ui-layout/tests` are authored but unexecuted.
This includes `ios_input_gate_checks.cpp`; grid pointer/resize scenarios are in
`card_selection_interaction_checks.md` and also remain unexecuted. Static review
cannot prove UIKit presentation, background/resume or teardown behavior on-device.
The resource phase can replace an older managed build-product package whose
baseline manifest is valid; this does not enable migration of user Documents data.
