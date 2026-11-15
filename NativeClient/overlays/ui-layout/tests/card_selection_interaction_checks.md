# Card grid interaction regression cases

Status: authored only. No native compilation, simulator, device or Actions run was performed.
The C++ layout checks exercise the production headers; they do not validate Irrlicht event dispatch.
Run the cases below with the actual client after the build hold is lifted.

| Case | Action | Required result |
| --- | --- | --- |
| Wheel over card art | Open a list with 61 cards; wheel over each of the three card rows, then over a label and scrollbar. | Each wheel step moves exactly one row through the existing scrollbar callback. The displayed cards and click indices agree. |
| Wheel during panel fade | Wheel over the art and scrollbar while the panel is opening or closing. | A disabled panel does not change its selection or scrollbar; no wheel event falls through to another panel. |
| Covered panel | With selection/display overlap during a transition, wheel over the front panel; repeat with Duel Tools covering the list. | Only the hit panel handles the event. Duel Tools keeps priority. |
| Hint over adjacent row | Hover a named card whose hint overlaps another row; tap/press and release a card under that hint. | The underlying card receives the click; the old hint does not stay as a hit target. |
| Reused unknown slot | Show a named-card hint, then scroll/refresh to a face-down card in the same slot. | No old name or old card image remains. The hidden card stays hidden. |
| Resize while opening | Resize between both halves of the panel opening animation. | The panel remains in the new safe-area rectangle, finishes opening, restores images and becomes enabled. |
| Resize while confirming | Confirm a valid selection; resize during either half of the closing animation. | The panel finishes closing and sends the queued engine response exactly once. |
| Partial final row | With 16, 19, 20 and 61 cards, scroll to the end and tap every visible slot. | Every card is reachable. Empty slots cannot activate a card. Responses use the original engine selection sequence. |
| Smaller follow-up list | From the last scroll row, advance to a smaller selection list. | Scroll/index state clamps to the new list; no stale image, label or out-of-range action survives. |
| Selection modes | Select/unselect ordinary cards, toggle mandatory sum materials, order cards, and use chain/special summon lists beyond the first 15 cards. | Required/selected counts and enabled confirmation match engine rules; mandatory cards cannot be toggled. |
| Keyboard confirmation | Focus Confirm/Cancel, activate with Return/Space and repeat while closing. | No duplicate response or activation of an unrelated button ID. |
| Small landscape screens | Inspect 568x320, 667x375 and notched 844x390 point layouts with safe areas. | Three rows, labels, scrollbar and footer remain in the panel; status text remains readable and Confirm/Cancel usable. |

Source basis for wheel/hover behavior: pinned Irrlicht commit
`5b93ec6a8bbfca61ae8a314386e4fa808dd81837`, `CGUIScrollBar::OnEvent` and
`CGUIEnvironment::postEventFromUser/updateHoveredElement`. Device behavior remains unverified.
