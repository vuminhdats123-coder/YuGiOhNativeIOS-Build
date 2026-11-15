# Canonical combo validation

`host-combo-validation-v9.json` records **6/6 real-core combo scenarios** (three
sequences from both player perspectives) on runtime v9a with the current
production AI. All reached their Lua completion marker with zero retries or
script errors.

| Combo | Verified result |
| --- | --- |
| Foolish Burial (`81439173`) → Monster Reborn (`83764718`) | Blue-Eyes White Dragon is sent from the own deck to the public GY, then revived face-up to the own field. Both spells reach the GY and final field/LP are asserted. |
| Trade-In (`38120068`) → Silver's Cry (`87025064`) | Blue-Eyes is discarded by Trade-In, then Silver's Cry targets that public Dragon in the GY and summons it. Both spells reach the GY and final state is asserted. |
| Reinforcement of the Army (`32807846`) → Junk Synchron (`63977008`) | ROTA searches Junk Synchron from the own deck, then it is Normal Summoned. Quillbolt Hedgehog remains a public Level-2 GY card and ROTA reaches the GY. This is deliberately reported as a completed two-step search/summon sequence: the core/AI did not complete a third Synchro action, so no Synchro victory is claimed. |

The fixture only sets cards and observes final state. It does not generate AI
answers, emulate card operations or reveal future deck order. The host snapshot
includes own hand/Extra identities and both public graveyards, while omitting
opponent private zones and Main Deck identities.

Before the profile change, the same core reproduced Foolish/Reborn and
Trade-In/Silver's Cry failures and a ROTA loop after search; those diagnostics
remain in `outputs/ocg-reference/combo-first.json` and `combo-js3.json`. They are
not counted as passes. The current profile recognizes Junk Synchron after it
reaches the field without exposing deck contents.

The report pins AI, adapter, harness, fixture, CDB and canonical Lua hashes. It
is bounded evidence of these sequences, not every combination or iOS runtime.
No compiler, Xcode, Actions or IPA build was run.

```powershell
python tests/test_ocg_matches.py
python tools/run_ocg_matches.py --scenario-suite combo --runtime outputs/edopro-game-v9a --seed 701
```
