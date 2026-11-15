# Native core validation on Windows (2026-11-15)

`host-validation.json` records **36 completed real OCG matches, 444 turns and
16,290 engine responses**, with zero `MSG_RETRY` responses and zero script errors.
35 matches ended by LP; one ended by deck-out (SuperQuant vs U.A., seed 111,
turn 46). Both sides use the same production JavaScript decision module in two
player perspectives. This is a bounded regression sample, not a claim that every
possible deck or effect interaction has been exercised.

The separate card-initialization pass created all **7,486 unique mapped OBB
codes** in 234 independent duels of at most 32 cards. It executed card
`initial_effect` and dependency loading, loading 6,872 canonical runtime Lua
files, with zero missing required scripts and zero errors. 640 absent scripts
belong to cards without scripted effects; `c0.lua` is the engine's empty-card
lookup. Initialization does not exercise every effect's activation/resolution.

The actual matches exercised prompt IDs 10, 11, 12, 13, 14, 15, 16, 18, 19, 20,
23, 26 and 143. The other eight implemented prompt families were not observed
in these games. A later [prompt-scenario report](HOST_PROMPT_VALIDATION.md)
exercises those eight, including announce-card, through the real core; together
the reports cover all 21 handled families, not all prompt variants or effects.
The host announce-card filter translates the pinned client's
`DataManager::IsCardDeclarable` and also has Python checks.

## Exact inputs and provenance

- Python 3.12.10 **32-bit embeddable ZIP**, downloaded from [Python.org](https://www.python.org/downloads/release/python-31210/).
  Its SHA256, `084b9eb24cb848605c895d05b738fbc2572efc8b4c18c415a824065864a2b853`,
  is published in the [official SPDX](https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-win32.zip.spdx.json).
  It is extracted only under `outputs/ocg-reference/python-3.12.10-win32`, with
  no global installation, PATH mutation, package installation or compiler.
- Official [ProjectIgnis/bin DLL](https://github.com/ProjectIgnis/bin/blob/a2d0ff9f28a184a572d4c5ae60f57e2e8343c820/ocgcore.dll),
  attributed upstream to core source `fd2a557167f9e0fe19b867c325e67a3b3f9dca11`.
  The harness verifies size, Git blob SHA1 and SHA256
  `cc066dfe50d0ad1fd47645634d058771b02292fec83b7ab1eb4f755e5f7f303b`
  before loading. PE architecture is x86, imports are kernel32/msvcrt, and the
  live `OCG_GetVersion` result is **11.0**.
- The iOS source pin is `46779fbe40e6a9bd8967f5dc6a03f4eaa6550d57`.
  `git diff` between the two commits changes seven build/deployment files only;
  core C++/headers and Lua gitlink `6e22fedb74cf0c9b6656e9fce8b7331db847c605`
  are identical. This is source equivalence, **not** the exact iOS binary or a
  reproducible-build assertion about the prebuilt DLL.
- `NativeClient/upstream.lock.json` supplies the CDB and canonical CardScripts
  archive hashes. Lua is read from the prepared runtime package, including its
  explicit script override. Every executed Lua file must match both the package
  manifest and content present in that verified canonical archive.
- Validated production JS SHA256:
  `e05fd0ac206d61ecb4e1d5fefd94c44adde9718cfce6d85df4a57478f118d57b`.
  Host adapter SHA256:
  `d33de18d218ad5dfdba5b4aef81db0ba3b69cac2d1f0b0b944a0b4f833ba0bb6`.
  The harness refuses to record a mixed-version result if either file changes
  during a run. Seeded deck shuffles, deck hashes, message counts and outcomes
  are recorded per match.

## Reproduce without building

From the repository root on Windows, with existing Node and a prepared runtime
package (now v6 by default), first obtain the verified DLL and the source commit object
needed by a shallow checkout. The recorded 36-match run used v3; later packages
add UI textures, NPC portraits and their reports. Database, Lua, decks and AI bytes
are unchanged. Those host games do not execute the newly changed client UI paths.

```powershell
python tools/smoke_ocg_host.py --download --report outputs/ocg-reference/host-smoke-preflight.json
git -C NativeClient/edopro/ocgcore cat-file -e fd2a557167f9e0fe19b867c325e67a3b3f9dca11
if ($LASTEXITCODE -ne 0) {
    git -C NativeClient/edopro/ocgcore fetch --no-tags --depth=1 origin fd2a557167f9e0fe19b867c325e67a3b3f9dca11
}
```

The smoke command verifies the downloaded DLL without loading it; a
`blocked_architecture` result under the ordinary 64-bit Python process is
expected. The fetch adds commit objects only and does not change the checked-out
source. Then run the isolated 32-bit validation:

```powershell
python tools/run_ocg_matches.py --download-python --suite --pool-check
python -m unittest discover -s tests -p test_ocg_matches.py -v
node NativeClient/overlays/offline-ai/offline_ai.test.js
```

The match command verifies/extracts portable Python, then launches a separate
32-bit worker. ctypes uses cdecl and checks the API-11 x86 struct sizes before
calling the DLL. The loop has step/turn limits, rejects retries, and reports
failures instead of substituting answers or pretending a match finished.
`--matches`, `--seed`, `--deck-a`, `--deck-b` and `--sample-decks` support smaller
runs; `--report` selects another report path.

Node loads `NativeClient/overlays/offline-ai/offline_ai.js` directly, and the
harness records/checks its hash before and after the run. It does not load the
runtime package's JS copy. That package copy has separately been refreshed to
the same final `e05fd0ac…118d57b` version; this distinction matters when
reproducing a run after editing the source.

The thirteen Python harness tests cover packet framing/rejection, YDK sections and
malformed decks, announce-card constraints, the pinned Python release, exact
scenario completion markers, response validation, and required effect evidence.

The separate [effect-scenario report](HOST_EFFECT_VALIDATION.md) adds eight
bounded scenarios with canonical card scripts and final-state assertions. It
does not add full matches to this report or establish iOS client behavior.

## Evidence boundary

No Xcode compilation, GitHub Actions run or IPA was produced. This host test
runs the engine, canonical scripts and production decision logic. It does not
run Objective-C++/JavaScriptCore, Irrlicht UI/touch input, the on-device asset
bootstrap, card rendering, audio, app lifecycle or a human-versus-bot UI session.
`iosRuntimeVerified` and `buildTriggered` remain false. The earlier
`host-smoke.json` is retained as the historical 64-bit-process blocker; this
report records its resolution using the isolated 32-bit process.
