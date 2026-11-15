# Real-core Synchro, Xyz and Link validation

`host-extra-deck-validation.json` records **10/10 successful bounded scenarios**:
five interactions, each executed from both player perspectives. The verified
precompiled Windows x86 OCG core accepted **106 production-AI responses**,
including **20 material-selection toggle responses**, with **zero retries and
zero core/Lua errors**. Production AI code was unchanged.

The fixture `../tests/fixtures/ocg_extra_deck_scenarios.lua` only supplies starting
positions and passive observation callbacks. Actual summon procedures, material
selection and card effects run through the pinned canonical card scripts and the
real core. No fixture calls a card's operation directly, copies a card effect,
manually summons the tested Extra Deck monster, or supplies scripted AI answers.

## Assertions exercised

| Scenario | Setup and canonical action | Verified result | Responses, both players |
| --- | --- | --- | ---: |
| Synchro summon and trigger | Junk Synchron (`63977008`) + Speed Warrior (`9365703`) summon Junk Warrior (`60800381`); Mokey Mokey (`27288416`) remains on the field | Exact two materials in the GY with material/Synchro reasons; proper Synchro summon in main monster zone 0; Mokey stays in zone 2; Junk Warrior's forced summon trigger raises ATK from 2300 to **2600**; LP 8000/8000 | 20 |
| Xyz summon and detach effect | Gene-Warped Warwolf (`69247929`) + Alexandrite Dragon (`43096270`) summon Gagaga Cowboy (`12014404`) | Rank 4, proper Xyz summon in main monster zone 0, face-up Defense Position; initially exactly those two overlay cards; then exactly one original material detached to the GY as Cowboy's cost and one still attached; effect damage leaves opponent at **7200 LP** | 28 |
| Link summon and optional trigger | The two differently named normal monsters summon Knightmare Phoenix (`2857636`); one Blue-Eyes White Dragon in hand pays the cost; opponent has a set Magic Jammer | Proper Link-2 summon in Extra Monster Zone 5; exact materials in the GY for Link/material reasons; Blue-Eyes discarded as cost; opponent's trap destroyed by Phoenix's actual effect; hand empty and LP 8000/8000 | 24 |
| Synchro summon negation | Opponent activates set Solemn Judgment (`41420027`) during the Junk Warrior summon-negation window | Defender pays half LP to **4000**; the attempt is negated; Junk Warrior is destroyed by Judgment and has no completed-summon status; both Synchro materials remain consumed; Mokey survives; no successful-special-summon message is emitted | 20 |
| Link rating as material contribution | A predefined Phoenix in Extra Monster Zone 5 and Junk Synchron in main monster zone 0 summon Decode Talker (`1861629`) | Proper Link-3 summon in Extra Monster Zone 5; exactly those **two** effect monsters are consumed, proving Phoenix contributes Link rating **2**; only Decode remains and its unboosted ATK is 2300 | 14 |

Each case makes two actual `MSG_SELECT_UNSELECT_CARD` material decisions. The
responses come from the production JavaScript parser and are validated by the
core. The Link-rating case checks the resulting legal summon, not merely a
synthetic arithmetic fixture. Xyz tests explicitly distinguish attached overlay
cards from a detached card in the GY.

The two Solemn Judgment cases pass because negation is the expected result. A
successful summon in either case fails both the Lua observer and the harness's
forbidden-message check (`MSG_SPSUMMONED`, 63). The eight positive cases each
produce one successful-special-summon message. Completion requires the expected
native messages, verified canonical-script loading and the exact player-specific
Lua marker emitted after the final-state assertions.

The first native run already passed all ten cases; no failing AI/core cases were
dropped or replaced. Review then added an idempotent observer guard so subsequent
`EVENT_ADJUST` callbacks cannot re-emit a marker after completion. The final run
passed all ten again. The initial diagnostic remains at
`outputs/ocg-reference/extra-deck-first-run.json`.

## Reproduce without compilation

From the repository root on Windows:

```powershell
python tests/test_ocg_matches.py
python tools/run_ocg_matches.py --extra-deck-scenarios --seed 401
```

The dedicated flag writes `NativeClient/host-extra-deck-validation.json` by
default. It cannot be combined with another scenario suite or match/pool options.
It uses the existing verified portable 32-bit Python and precompiled core; no
compiler is involved.

**14 pure Python harness tests passed.** Because the shared scenario runner was
extended, both older suites were rerun to separate diagnostic paths:

- Prompt suite: **6/6**, **54 responses**, zero retries/errors,
  `outputs/ocg-reference/extra-deck-prompt-regression.json`.
- Canonical-effect suite: **8/8**, **112 responses**, zero retries/errors,
  `outputs/ocg-reference/extra-deck-effect-regression.json`.

The earlier 36-match report and the historical prompt/effect reports were
preserved. The unchanged normal-match path and production AI did not require a
repeat of the 36-game suite. No new full-game victories are claimed by this
Extra Deck report.

## Provenance and scope

The report records hashes of the harness, fixture, AI, host adapter, CDB and
canonical Lua archive; required executed-script hashes; native event payloads;
actual prompt/response bytes; expected/forbidden messages; and completion markers.
Runtime Lua must match both the package manifest and verified canonical archive.

- Production AI SHA256:
  `e05fd0ac206d61ecb4e1d5fefd94c44adde9718cfce6d85df4a57478f118d57b`
- Extra Deck fixture SHA256:
  `77d66b1a25ecb770a0b8376769b60cbf57cfadaae44bd09be490410328647cbd`
- Harness SHA256:
  `d5f24a2ab1c6253759dd6f8aa2784a4f1969bae3c615777a32c93326b0589b1a`
- Official precompiled core SHA256:
  `cc066dfe50d0ad1fd47645634d058771b02292fec83b7ab1eb4f755e5f7f303b`

Starting boards are predefined, opening/per-turn draws are zero, and each
scenario is limited to 500 core-processing steps plus the worker's outer timeout.
These tests demonstrate the selected legal interactions, not every material
restriction, summon alternative, card effect or AI strategy. In particular, they
do not exercise Cowboy's Attack Position effect, Phoenix's co-linked draw,
Decode Talker's negation, or all possible negative-material combinations.

The official precompiled core revision and the iOS source pin have identical
core C++/headers and Lua gitlink, with seven build/deployment-file differences.
This supports source equivalence, not an identical or reproducible iOS binary.
The scenarios do not execute the iOS bridge, native selection UI, touch input,
rendering or device lifecycle. No native compilation, Xcode, GitHub Actions or
IPA build was run; `fullMatchesExecutedThisRun` is zero, and `buildTriggered` and
`iosRuntimeVerified` remain false.
