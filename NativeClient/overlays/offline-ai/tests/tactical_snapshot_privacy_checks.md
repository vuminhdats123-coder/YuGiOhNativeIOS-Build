# Native tactical snapshot boundary checks

Status: authored, **not run**. Do not compile/build while the user's build hold remains active.
Node/host-core checks do not prove the Objective-C++ bridge or iOS GUI runtime.

The fifth `decide` argument is `{self, opponent}`. Each side has `lp`, `handCount`,
`deckCount`, `extraCount`, and `cards` containing only Monster/Spell/Trap Zone occupancy.
Face-down records contain only `code: 0`, `location`, `sequence`, and `position`.
Face-up records add current `type`, `attack`, `defense`, `level`, `rank`, `link`, `disabled`.
The self side additionally has `hand` and `extra` arrays with the same fields, queried
directly from the duel core on the duel thread. Both sides have public `grave` arrays.
The opponent side has no `hand` or `extra` identities. No Main Deck order or identity is
queried. Own hand/Extra access is authorized for combo planning; no future draw position is
provided.

After native testing is authorized:

1. Inspect the actual JavaScriptCore fifth argument at an AI prompt while a public monster
   has a changed ATK/DEF. Values must equal the refreshed `ClientCard`, not database base stats.
2. Pair two otherwise identical duels with different opponent hand identities, deck orders
   and set-card identities/stats. Snapshot fields must be identical except public counts
   if deliberately changed. The self hand/Extra records may differ only when the AI's own
   legal cards differ; opponent hand/Extra records must never be present.
3. Turn a previously face-up card face-down. Its remembered `ClientCard::code`, type,
   ATK/DEF, rank/link and disabled status must not reappear in the next snapshot.
4. Check the mapping with `dInfo.isFirst` both true and false. `self` and `ownPositions`
   must always refer to core player 1, `opponent` to core player 0, via `LocalPlayer`.
   Control-changed monsters belong to their current on-field side.
5. Trace calls to JS `observe`: raw draw, shuffle, deck-top, confirm-card, move and battle-stat
   messages must never arrive. An opponent's selection hint must not arrive either.
   A public chain effect may identify its handler, but private-zone sequences must be zero.
6. Inspect face-down special-summon notifications: their public position/zone may be
   forwarded, but code bytes must be zero. Face-up summon identities remain available.
7. Inspect the actual second `decide` argument for SELECT_CARD/UNSELECT/TRIBUTE/SUM.
   The existing stateless selector redactor must have zeroed hidden opposite-player identities
   before the strategy receives it. Payload entry indices, controller/location and
   contribution values must remain unchanged. Decision-only `hideDeckOrder=true` must
   zero Deck selector sequences while preserving own legal search candidate codes.
   Public Graveyard/overlay/face-up field
   and banished identities remain available, as do own legal deck-search candidates.
   Repeat with different hidden opponent candidate codes and confirm identical decisions.
8. Exercise the same deck-search prompt through the human `ClientAnalyze` path. Its
   default `hideDeckOrder=false` must preserve the original deck sequences needed by
   `GetCard`. Selecting a nonzero-index candidate must still reference and submit the
   correct card. The AI path alone passes `true`; its response entry indices stay intact.
9. Verify the expanded core query bridge: own hand and Extra identities match
   `DuelQueryCount`/`DuelQuery` results on the current duel thread; both Grave arrays contain
   only public card records; Main Deck is never queried. A large Grave is capped at the
   documented bridge bound without affecting legal prompt candidates.

`observation_privacy_checks.cpp` directly exercises the production whitelist/redaction
helper, including malformed lengths and private-zone sequence normalization. It remains
unexecuted. Snapshot serialization, current-stat refresh and GUI/player mapping still need
the native checks above.
