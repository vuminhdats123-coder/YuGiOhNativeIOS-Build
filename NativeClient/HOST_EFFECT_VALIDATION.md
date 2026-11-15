# Canonical card-effect scenarios on the real core

This historical report used the previous AI and fixtures that implicitly ORed
MR3 options into MR5. Current fixtures pass rule=0 and verify effective rules.
Their v7 regression passed; see [the correction and new evidence](HOST_RITUAL_PENDULUM_VALIDATION.md).

`host-effect-validation.json` records **8/8 successful bounded scenarios**: four
interactions, each exercised from both player perspectives. The official
precompiled Windows x86 OCG core accepted **112 production-AI responses**, with
**zero `MSG_RETRY` and zero Lua/core errors**. No production AI changes were needed.

These checks extend the earlier match and prompt evidence by asserting the
resulting game state after real card effects resolve. The test fixture creates a
small starting field and registers observation callbacks. The existing AI chooses
legal actions, the actual core builds/resolves chains, and the pinned canonical
card scripts perform all card effects. The fixture neither invokes the card
operations directly nor replaces them with simulated destruction, summoning,
damage or negation.

## Verified interactions

| Scenario | Canonical cards/scripts | Final-state assertions before completion |
| --- | --- | --- |
| Destruction followed by revival | Dark Hole (`53129443`), Monster Reborn (`83764718`) | Both field monsters were destroyed by Dark Hole for effect/destruction reasons. Monster Reborn returned Blue-Eyes White Dragon to its controller's field; Dark Magician remained in the GY. Both spells reached the GY, exactly one monster remained on the field, and both players retained 8000 LP. |
| Spell activation negation | Dark Hole, Magic Jammer (`77414722`) | The core emitted chain-negation evidence for Dark Hole. Magic Jammer's discard reached the GY with cost/discard reasons; Dark Hole and Magic Jammer reached the GY. Both original monsters survived and LP stayed 8000/8000. |
| Effect damage and battle damage | Tremendous Fire (`46918794`), Blue-Eyes White Dragon | The spell changed LP to 7500 for its controller and 7000 for the opponent. A subsequent direct attack caused exactly 3000 battle damage; the Damage Step observer verified final LP 7500/4000 and the attacker remained on the field. |
| Fusion Summon from the Extra Deck | Polymerization (`24094653`), Blue-Eyes Ultimate Dragon (`23995346`), canonical Fusion procedure | Blue-Eyes Ultimate Dragon reached its controller's field face-up with Fusion summon type. Its material group contained exactly the three supplied Blue-Eyes White Dragons, all in the GY with material/Fusion reasons. Polymerization reached the GY, the hand was empty, and LP stayed 8000/8000. |

The damage scenario enables the core's first-turn-attack option to keep the test
short; this is explicitly test setup, not a change to normal game rules. Starting
fields are predefined and opening/per-turn draws are zero. Player-1 cases pass
through the other player's opening turn before the tested interaction.

Completion means the fixture's observer passed its assertions and emitted the
exact `HINT_MESSAGE` marker expected for that player/scenario. A core win before
that marker is treated as failure. These runs claim **zero complete games** and
never manufacture a winner. Required native event messages and canonical-script
loads are checked in addition to the Lua assertions.

## Reproduce without compiling

From the repository root on Windows:

```powershell
python tests/test_ocg_matches.py
python tools/run_ocg_matches.py --effect-scenarios --seed 301 --report outputs/ocg-reference/effect-current.json
```

The runner relaunches under the existing hash-verified 32-bit portable Python and
loads the verified precompiled core. No compiler is invoked. Its default output
for this suite is `NativeClient/host-effect-validation.json`, keeping
`host-validation.json` (36 historical games) and `host-prompt-validation.json`
(six historical prompt scenarios) intact.

**13 pure Python harness tests passed.** The shared scenario runner was also
regression-checked with the existing prompt fixtures: 6/6 scenarios and 54
responses, zero retries/errors. That separate result is
`outputs/ocg-reference/effect-runner-prompt-regression.json`; it does not replace
the historical prompt report. The full 36-game suite was not rerun because the
production decision module and normal-match path were unchanged.

## Inputs, evidence and limits

The report records the fixture and harness hashes, pinned CDB and CardScripts
archive hashes, loaded required-script hashes, actual native event payloads,
actual AI responses, expected messages and scenario completion markers. Every
loaded runtime Lua file must still match its package-manifest hash and content
from the canonical CardScripts archive. The flattened runtime paths such as
`c53129443.lua` are the actual loaded keys; their origin is the canonical script
archive, not a replacement test implementation.

- AI SHA256:
  `e05fd0ac206d61ecb4e1d5fefd94c44adde9718cfce6d85df4a57478f118d57b`
- Test Lua SHA256:
  `fcb4387e702bf3f14e0f8c12fe24a4f322925e62759d07d713daaf3f7e515f9c`
- Harness SHA256:
  `9eb057c02aa9d6d0cbad74ae6cfdbb8b8132e35c8e7437c3f98007114c2f303b`
- Precompiled core SHA256:
  `cc066dfe50d0ad1fd47645634d058771b02292fec83b7ab1eb4f755e5f7f303b`

Each scenario has a 500-processing-step limit, and the isolated worker has an
outer timeout. Fixture, harness and production-AI/adapter bytes must remain
unchanged during a run. The report retains the existing source-equivalence
qualification: the official precompiled core's revision differs from the iOS
source pin only in seven build/deployment files, with identical core C++/headers
and Lua gitlink. This is not an identical-iOS-binary or reproducible-build claim.

Coverage is limited to these selected interactions and starting states. It does
not establish every effect, targeting rule, damage modifier, negation window,
Extra Deck summon method, or strategic quality of the AI. It does not execute
Objective-C++/JavaScriptCore, Irrlicht rendering, human touch selection, lifecycle
transitions, or an iPhone package. No Xcode compilation, GitHub Actions, IPA build
or device test was run; `buildTriggered` and `iosRuntimeVerified` remain false.
