# Ritual and Pendulum validation on the real core

`host-ritual-pendulum-validation.json` records **12/12 successful scenarios**,
covering six interactions from both player perspectives. The actual precompiled
OCG core accepted **128 production-AI responses**, including four Ritual sum
selections and twelve Pendulum selection toggles, with zero retries or core/Lua
errors in the final run. This report uses runtime package v7 and the corrected
production AI.

## Reproduced and fixed AI behavior

The old AI finished `MSG_SELECT_UNSELECT_CARD` immediately when the core first
allowed finishing. In a Pendulum Summon with a legal hand monster and a legal
face-up Extra Deck monster, it selected the hand monster and then returned `-1`
while the Extra Deck candidate was still selectable. The response was legal, but
the AI failed to perform the intended multi-monster Pendulum Summon.

This was reproduced for both players before the production change. A second
baseline replay used the corrected, explicitly verified MR5 setup and an isolated
hash-verified copy of the old AI, leaving the production source untouched.
`host-ritual-pendulum-baseline.json` retains those two expected failures, including
the native prompt bytes, the premature `-1` response and the failed group-size
assertion. It is historical failure evidence, not a failing result for the current
AI. Both baseline scenarios recorded effective rule options **190464 / 0x2e800**.

The production fix continues selection when the public prompt hint is special
summoning and all listed selectable/selected cards belong to the AI in its hand
or face-up Extra Deck. Other prompts retain their previous finish behavior. The
core still determines which candidates and zones are legal. The final canonical
scenarios verify the resulting summon groups, not just the response format.

## Verified interactions

| Scenario | Canonical action | Assertions after the real core resolves it | Responses, both players |
| --- | --- | --- | ---: |
| Exact Ritual total | Gishki Aquamirror (`46159582`) summons Evigishki Gustkraken (`45222299`) | Exactly the two supplied Level-3 Silver Fangs are consumed for release/material/Ritual reasons; total Level is exactly 6; Ritual summon/procedure completes; the unused Level-8 Blue-Eyes stays in hand | 30 |
| Greater Ritual total | Black Luster Ritual (`55761792`) summons Black Luster Soldier (`5405694`) | Exactly one Level-10 Tragoedia is consumed, exceeding the Ritual monster's Level 8; release/material/Ritual reasons and completed Ritual summon are checked | 18 |
| Mixed Pendulum and strict scale bounds | Dragonpulse Magician / Dragonpit Magician scales 1 and 8 | Speed Warrior (Level 2) from hand and Dragon Horn Hunter (Level 6) from face-up Extra are summoned together; the hand monster uses a main zone and the Extra monster uses EMZ 5; Level-1 and Level-8 endpoint monsters remain in hand | 20 |
| Face-up Extra without Link arrows | Two eligible face-up Pendulum monsters in the Extra Deck | Exactly one can be summoned into EMZ 5; the other remains face-up in the Extra Deck despite empty unlinked main zones | 14 |
| Face-up Extra with Link arrows | Decode Talker already occupies EMZ 5 | Both eligible Extra Deck Pendulum monsters are summoned into exactly main zones 0 and 2, which Decode Talker actually points to | 20 |
| Destruction and return from Extra | Dark Hole destroys Dragon Horn Hunter on the field | Canonical destruction sends it face-up to the Extra Deck, not the GY; the AI then Pendulum Summons it into EMZ 5; destruction/effect reason, Dark Hole identity and previous Extra Deck location are checked | 26 |

Both players retain 8000 LP in these scenarios. Starting boards and opening draws
are predefined. The fixture supplies setup and passive observers only; canonical
scripts perform Ritual/Pendulum procedures, material release and destruction.
There are no synthetic effect operations, manually constructed prompt packets or
fixture-generated victories. Completion markers are emitted only after the
final-state assertions pass.

## Effective-rule correction

The pinned `Debug.ReloadFieldBegin` API defaults its second argument to rule 3,
which ORs MR3 options into the requested options. Passing MR5 as the first
argument alone therefore did not establish a strictly MR5 fixture. Current
scenario fixtures now pass an explicit second argument of **0**.

The harness reads the effective rule bits from actual `MSG_RELOAD_FIELD` output
and rejects any mismatch. Ritual/Pendulum scenarios must report exactly
**0x2e800**, and their scale cards must occupy merged Pendulum slots **0 and 4**.
The only permitted first-turn-attack override is explicitly requested by the two
older attack-cost/damage test scenarios; their expected options are **0x2e802**.
The pure harness test also rejects accidental separate-Pendulum-zone bits.

Earlier scenario JSON reports remain unchanged as historical evidence; their
fixture options must be qualified as mixed MR3/MR5. The ordinary 36-match harness
did not use `Debug.ReloadFieldBegin` and is not affected by that fixture bug.
Current corrected fixtures were regression-tested with the new AI in
`host-scenario-regression-v7.json`.

## Reproduce without compiling

From the repository root on Windows with prepared runtime v7:

```powershell
python tests/test_ocg_matches.py
python tools/run_ocg_matches.py --scenario-suite ritual-pendulum --seed 501
```

The named suite mechanism also accepts `prompt`, `effect` and `extra-deck`.
Existing `--prompt-scenarios`, `--effect-scenarios` and
`--extra-deck-scenarios` flags remain compatible aliases; selecting multiple
suites together is rejected. Reports use separate default paths, and `--report`
selects a diagnostic output without overwriting historical evidence.

**15 pure Python harness tests passed.** The corrected older suites were rerun
with v7 into the consolidated regression report: 6 prompt scenarios, 8 canonical
effect scenarios and 10 Extra Deck scenarios: **24/24 passed, 272 responses,
zero retries/errors**. Twenty use strict MR5; four use the intentional
first-turn-attack override. Each scenario verifies effective rule options and the
same production AI hash. Their full-game count remains zero.

## Provenance and limits

Final reports retain hashes for the fixture, harness, production AI/adapter,
pinned database, canonical Lua archive and required executed scripts, alongside
native events, prompts/responses, completion markers and effective rule options.
Runtime scripts still must match both their manifest hashes and the canonical
archive. Each scenario is bounded to 500 core-processing steps and the worker has
an outer timeout.

- Old AI SHA256 (baseline):
  `e05fd0ac206d61ecb4e1d5fefd94c44adde9718cfce6d85df4a57478f118d57b`
- Corrected AI SHA256:
  `ea8ca399e292ff98719e2231465c97ac53caf15d4a062b64b4fd0cf1529b168e`
- Ritual/Pendulum fixture SHA256:
  `df63ed3b054005be418c59d5d341514df6262f3fec8b44b69274758b0a31e7ad`
- Harness SHA256:
  `502bef8054408a5e12e39900cdbaa990902ce4b06ac1bd70f757c963218c3d07`
- Official precompiled core SHA256:
  `cc066dfe50d0ad1fd47645634d058771b02292fec83b7ab1eb4f755e5f7f303b`

Coverage is bounded to these cards and starting states. It does not establish all
Ritual alternate materials, restricted Pendulum summons, summon-negation cases,
card-effect interactions or AI strategies. The configured official precompiled
core and iOS pin share core C++/headers and Lua gitlink but differ in seven
build/deployment files; this is source equivalence, not identical-iOS-binary proof.
No Objective-C++/JavaScriptCore UI session or iPhone runtime was tested here. No
compiler, native build, Xcode, GitHub Actions or IPA build was run.
