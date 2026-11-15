# Tactical AI, chain and Damage Step checks

`host-tactical-validation.json` records **14/14 successful cases**, seven
canonical tactical scenarios from both player perspectives, with **181 actual
AI responses, zero retries and zero core/Lua errors** on runtime v8. The fixture supplies starting positions and passive
assertions; the real precompiled OCG core, canonical scripts and production AI
make and resolve the actions. No fixture supplies AI responses, reproduces card
operations or manufactures a victory.

Final result: **14/14 passed, 181 responses, zero retries/core/Lua errors**.
All **36 earlier scenarios passed again**, with 388 responses and zero errors,
in `host-scenario-regression-v8.json`. Full-match results are separate in
[HOST_VALIDATION_V8.md](HOST_VALIDATION_V8.md).

## What the paired scenarios verify

| Case | Expected real play and resulting state |
| --- | --- |
| Reject a bad Dark Hole trade | With Blue-Eyes and Dark Magician against one Mokey Mokey, preserve both own monsters and retain Dark Hole through the AI's End Phase. Activation is an immediate assertion failure. |
| Take a favorable Dark Hole trade | With one Mokey against Blue-Eyes and Dark Magician, activate Dark Hole and destroy all three through its canonical effect. |
| Use Magic Jammer to save the board | Negate a threatening Dark Hole, pay the low-value Yubel discard as a real cost, preserve both original monsters and consume both spells/traps. Native chain-solving messages must occur in order **2, then 1**, with link 1 negated. |
| Retain Magic Jammer against Upstart | Let Upstart Goblin resolve, draw one card and grant the defender 1000 LP; preserve the set Jammer and its potential discard instead of spending two cards on a minor effect. |
| Do not mistake MST for negation | Let the normal Dark Hole resolve and retain Mystical Space Typhoon. The chain must contain only Dark Hole; destroying an activated normal Spell would not negate its effect. |
| Use Rush in the Damage Step | La Jinn's visible 1800 ATK cannot beat a 2000-ATK Warwolf. Activate Rush Recklessly during the actual Damage Step before calculation, reach 2500 ATK, destroy Warwolf in battle and deal exactly 500 damage. Both attacking and defending perspectives are exercised. |
| Retain Rush when already winning | La Jinn already beats a 1700-ATK Battle Ox. Keep Rush set, preserve the 1800 ATK and deal exactly 100 damage; activating Rush fails the test. |

The two Rush cases explicitly enable first-turn attacks to keep the tests short.
Their actual rule options must be MR5 plus that override; all other tactical cases
must report strict MR5. Core retries, script errors, a premature duel victory or
failure to reach the exact completion marker fail the scenario.

## Actual historical failures

`host-tactical-baseline.json` preserves six deliberate baseline failures: the old
AI `ea8ca399…dae73f` was loaded from Git into an isolated directory with the safe
host adapter, without replacing production files. For both player perspectives
it used the harmful Dark Hole, spent Jammer plus a discard on Upstart, and used
Rush before the requested Damage Step window. These were legal wire responses
with zero retries; the failures are tactical assertion failures, not claims that
the old core accepted illegal moves. Activating Rush earlier can be legal, but it
fails this policy's requirement to retain the card until that battle needs it.

During development one additional failure came from the new End Phase observer:
it remained eligible on the other player's turn and repeatedly reopened phase
processing. The fixture now gates the observer with a condition before its
operation. This was a fixture bug, not an AI retry or a reason to omit the case.

## Information available to the AI

The fifth decision argument is a side-relative snapshot:

```text
board.self / board.opponent:
  lp, handCount, deckCount, extraCount,
  cards: on-field MZONE/SZONE occupancy only
```

Face-up known field cards include code, location, sequence, position, current
type/ATK/DEF/Level/Rank/Link and disabled status. Every facedown or unknown card
contains only code 0, location, sequence and position, on both sides. There are
no hand, deck or Extra Deck identity arrays in the snapshot. The host reads only
counts/occupied positions from `OCG_DuelQueryField` and queries card identities
and dynamic stats only for face-up field slots. Python tests verify that hidden
slots and private locations never receive a card-identity query.

The adapter projects onto this exact schema before calling the strategy. Its
observation gate only forwards validated public turn/phase, summon, chain,
attack and Damage Step messages, plus that bot's own selection hints. Raw draw,
shuffle, deck-top, move and battle-stat streams are not forwarded. Hidden summon
identities are cleared; private current/trigger sequences in declared chain
events are cleared. The same policy is implemented in the native bridge.

Decision prompts pass through the shared privacy projection before `decide`.
Opposing hidden identities are removed while public graveyard/face-up identities
and legitimate own choices remain usable. Legal own deck-search card identities
and response-list indices are retained, but deck sequence fields are cleared in
the decision-only copy. The default human projection retains sequences needed
by the native card-selection UI. No RNG seed, next-draw field or shuffled deck
order is supplied in the snapshot or observation stream.

The tactical report retains the safe snapshots used at each decision, alongside
native prompt bytes and actual responses. Native diagnostic bytes in a report
are not the same as the redacted input delivered to the AI; adapter spy tests
exercise the actual boundary before `observe` and `decide`.

## Older fixtures updated for sensible play

Current earlier-suite fixtures were adjusted instead of forcing the strategy to
make bad trades or bypassing checks:

- Destruction/revival now faces a stronger opposing board so Dark Hole is useful;
  the same destruction reasons and subsequent real revival remain asserted.
- Spell-negation now protects a valuable defender against a favorable opposing
  board wipe and uses a cheap Yubel discard.
- The Cowboy burn case faces a stronger monster, making Defense Position and
  its 800-damage effect preferable to a free attack on an empty field.
- Pendulum destruction/return now clears a stronger opposing board before the
  destroyed Pendulum monster returns from the face-up Extra Deck.
- The generic yes/no prompt checks that the core resumes with a boolean result;
  an unspecified question no longer requires an arbitrary “yes”. It still issues
  and completes the actual prompt.

All historical JSON reports remain unchanged. Current regression evidence is
stored separately in `host-scenario-regression-v8.json`: **36/36 earlier
scenarios, 388 responses, zero retries/errors**. Thirty-two use strict MR5 and
four retain the intentional first-turn-attack override. No skipped scenario is
counted as passed. The tactical cases add ten strict-MR5 and four intentional
first-turn-attack cases; these are not additional full games.

## Reproduce and evidence limits

From the repository root with runtime v8 prepared:

```powershell
python tests/test_ocg_matches.py
python tools/run_ocg_matches.py --scenario-suite tactical --seed 601
```

The harness has **19 pure Python tests**, including dynamic query parsing,
hidden-slot exclusion, exact rule flags and one-byte native chain-order events.
Reports pin AI, adapter, fixture, harness, database, canonical script archive and
required loaded scripts. Each scenario has a 500-processing-step bound plus the
worker timeout. Completion is scenario acceptance, not a full-game victory.

These tests cover selected tactical profiles and known boards. They do not prove
optimal combo planning, every card interaction, or a universal win rate. The
actual native iOS bridge, rendering, touch input and lifecycle were not executed
by this Windows harness. The precompiled core is source-equivalent to the pinned
iOS core with the previously documented build-file differences; it is not an
iOS binary. No compiler, Xcode, GitHub Actions, native app build or IPA build was
run for this verification.
