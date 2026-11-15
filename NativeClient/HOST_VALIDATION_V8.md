# Windows core regression with visible-state tactical AI

`host-validation-v8.json` records **36 completed matches, 609 turns and 14,955
responses**, with zero retries or Lua/core errors. Thirty-four matches ended by
LP and two by deck-out. Both sides use the current production AI and safe public
board/observation adapters. These are the same bounded deck/seed regression
cases as before; this is not an old-versus-new win-rate benchmark.

The [tactical report](HOST_TACTICAL_VALIDATION.md) adds 14 canonical scenarios
with 181 accepted responses. Its separate regression report covers all 36 earlier
scenario cases with 388 responses. Some earlier starting boards were adjusted
to make the tested actions strategically sensible; no case was omitted. Those
scenarios are not counted as complete matches.

`offline_ai_privacy.test.js` verifies the actual pre-observer/pre-decision
boundary and hidden-information invariance for both players. The main JS tests
cover paired tactical decisions and Damage Step behavior. The Python suite ran
84 tests: 83 passed and one symlink fixture was skipped on this Windows host.

Runtime v8 contains 46,163 files and 424,875,146 bytes. Its complete file manifest
differs from v7 only at `offline-ai/offline_ai.js`; database, Lua, deck, image,
portrait, audio and locale bytes are unchanged. The full resource-copy fixture
verified every hash and all 17 icons; it is not an executable app.

- AI SHA256: `d74846dd50dbbaa10548c4502ab8f78d3033c300f6066561af88c4c109dae73f`
- Manifest SHA256: `bc7c087c01130e19ebab7708d7ac7bdc131d1f34524ac517acc92dd188b2d7a0`

Repeat the current full-match regression without compilation:

```powershell
python tools/run_ocg_matches.py --suite --runtime outputs/edopro-game-v8 --report outputs/ocg-reference/full-suite-v8-current.json
node NativeClient/overlays/offline-ai/offline_ai.test.js
node NativeClient/overlays/offline-ai/offline_ai_privacy.test.js
```

The official precompiled core's provenance and source-equivalence qualifications
remain unchanged. The historical 7,486-card initialization evidence still uses
the same database/Lua bytes; it was not rerun. AI coverage is limited to the
[documented tactical profiles](AI_TACTICS.md), not universal combo planning.
Native C++/Objective-C++ assertions, the JavaScriptCore bridge and iPhone GUI
remain unexecuted. No compiler, Xcode build, GitHub Actions or IPA was run.
