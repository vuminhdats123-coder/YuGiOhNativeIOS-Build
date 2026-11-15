# Windows core regression with the Pendulum AI fix

Historical v7 evidence. The current tactical AI, adapters and scenario setups
have a separate [v8 regression report](HOST_VALIDATION_V8.md); the figures below
are not results for the latest production module.

`host-validation-v7.json` records 36 completed matches with the v7 production AI:
437 turns, 16,160 responses, zero retries and zero Lua/core errors. Thirty-five
matches ended by LP and one by deck-out. These are the same bounded deck/seed
cases as the historical regression suite, executed again after the AI changed.

The runtime package contains 46,163 files and 424,855,797 bytes. Comparing its
complete file manifest with v6 shows exactly one changed entry:
`offline-ai/offline_ai.js`. Database, canonical Lua, decks, pictures, portraits,
audio and locale files are unchanged. Every resource hash was checked during
copy into a resource-only fixture; it contains no native executable.

- AI SHA256: `ea8ca399e292ff98719e2231465c97ac53caf15d4a062b64b4fd0cf1529b168e`
- v7 manifest SHA256: `2670f116a9ccbb80fc016f1f5a527e4445f2639d978e627e3c04eb0b48a98e44`

The separate [Ritual/Pendulum report](HOST_RITUAL_PENDULUM_VALIDATION.md) records
12 new successful scenarios and a 24-case regression of the corrected older
scenario fixtures. Those scenarios are not counted as full matches here. The
historical 7,486-card initialization check was not rerun: the database and Lua
bytes it tested remain unchanged. See [its original evidence](HOST_VALIDATION.md).

To repeat the full-match regression without compilation:

```powershell
python tools/run_ocg_matches.py --suite --runtime outputs/edopro-game-v7 --report outputs/ocg-reference/full-suite-v7-current.json
```

The official precompiled x86 DLL, ABI/API and source-equivalence checks remain
in force. This validates selected core/script/AI interactions on Windows; it
does not run the native human-selection UI, JavaScriptCore bridge, card renderer
or iPhone lifecycle. Native Ritual selection checks have been authored but not
compiled/executed. No compiler, Xcode build, Actions run or IPA was produced.
