# Offline AI tactics and information boundary

The production JavaScript uses the current visible board to compare actions.
It prioritizes useful removal before committing another monster, avoids clearly
losing attacks into known stats, selects a defense position where appropriate,
and prefers lower-value discard/tribute costs. Its named effect profiles cover
22 cards: Dark Hole, Raigeki, Monster Reborn, Mystical Space Typhoon, Solemn
Judgment, Magic Jammer, Forbidden Chalice, Rush Recklessly, Mirror Force, Negate
Attack, Polymerization, Black Luster Ritual, Pot of Greed, Graceful Charity,
Upstart Goblin, Fissure, Smashing Ground, Book of Moon, Gishki Aquamirror,
Knightmare Phoenix, Gagaga Cowboy and Tremendous Fire.

Examples checked by paired decisions include retaining Dark Hole when it would
destroy a stronger friendly board, spending Magic Jammer to prevent serious
losses while retaining it against a low-value spell, and using Rush Recklessly
in the Damage Step to change a battle outcome or achieve lethal damage. MST is
not treated as an activation negate for a Normal Spell. Current field values
take precedence over printed stats for visible monsters.

This is a bounded heuristic policy. It is not a general combo planner or an
effect-script interpreter. Unknown optional effects are declined with a live
board context; forced choices still use the protocol handlers. Special summons
and material choices remain subject to core legality. The snapshot omits hand
and Extra Deck identities, so the AI cannot plan whole-hand/Extra-Deck combos
before a legal prompt exposes the relevant own candidates. These limits must not
be described as expert play for every card or deck.

## What reaches the decision code

The fifth `decide` argument contains relative `self`/`opponent` LP, public zone
counts and on-field cards. Visible cards include current type, position,
ATK/DEF, Level/Rank/Link and disabled state. Face-down or unidentified cards
contain occupancy/position only, with no identity or stats. Neither side's hand,
Main Deck or Extra Deck identity arrays, shuffle seed or next-draw information
are included. The host queries detailed card data only for visible field slots.
Native code copies the equivalent client state under the render mutex and maps
the view back to core player IDs.

Before `observe`, native and Node adapters allow only the needed public event
families and the selecting AI's own selection-purpose hint. Draw, shuffle,
deck-top, move, private reveal and hidden battle-stat packets are dropped.
Face-down summon identities and sequence offsets in private piles are removed.
An effect's publicly declared activation identity remains available for chain
evaluation. The JS observer also ignores irrelevant/private event families.

Before `decide`, selector prompts redact opposing hidden identities while
retaining original list indices. Deck sequence offsets are zeroed in the AI's
selector view; the human UI retains them for its existing card lookup. Public graveyard/overlay and face-up field or
banished identities remain usable. Own candidates exposed by a legal search or
selection are allowed for that choice; the AI does not reconstruct future draw
order from them. Static metadata describes card rules/stats, not which cards a
player holds or the order of either deck.

## Checks and limits

`offline_ai_privacy.test.js` spies before the actual observer/decision boundary:
private packets must not arrive, snapshots must discard private arrays/stats,
hidden selector identities must be zero, public GY/search choices must survive,
and changing hidden identities/order with the same known state must preserve the
decision. Tests run for both player perspectives. The main JS tests separately
check tactical choices, live stats, chain identities and Damage Step windows.

The native policy has authored assertions in
`overlays/offline-ai/tests/observation_privacy_checks.cpp` and manual cases in
`tactical_snapshot_privacy_checks.md`; they have not been compiled/executed.
Passing the host tests is not proof of an on-device JavaScriptCore/UI session,
perfect strategy, or coverage of every possible effect interaction.
