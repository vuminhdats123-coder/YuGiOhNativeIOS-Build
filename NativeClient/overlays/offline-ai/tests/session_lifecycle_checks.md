# Native offline session checks

Status: authored, **not run**. The user's build hold is still active. These cases require
the real GUI/duel threads; JavaScript/core-host tests do not establish their results.

## Close acknowledgement before the worker waits

1. Finish or leave an offline duel. Break the duel worker immediately after it sets
   `mainGame->closeDuelWindow = true`, before `closeDoneSignal.Wait(lock)`.
2. Continue the GUI thread alone. It must wait for `gMutex`; it must not finish
   `CloseDuelWindow()` or notify `closeDoneSignal` while the worker still owns that mutex.
3. Continue the worker into `Wait(lock)`, then both threads. The GUI closes once, clears
   `closeDuelWindow` and notifies; the worker finishes cleanup and returns.
4. Start another duel. It must pass the previous thread's join and reach a human prompt.

Also repeat after a restart whose deck/script initialization fails, which uses the
same close acknowledgement before restoring the offline menu.

## Stop and shutdown at each wait boundary

Exercise a pending human choice, an automatic no-chain answer, a card-reveal
acknowledgement, an LP animation and the win animation. For each boundary:

- Leave the duel and start a new one: no old response may reach the new core, and no
  reveal/selection window may remain active over the offline menu.
- Trigger the normal `Game::MainLoop` shutdown path: after its frame/close signals
  become nonblocking, `StopPlay(true)` must join the duel worker before Game teardown.
- Repeat Stop while cleanup is already underway. It must not reopen a prompt or
  reset a stopped mailbox into an accepting state.

The existing `response_mailbox_checks.cpp` directly checks the production mailbox's
early response, duplicate rejection, stop-before/while-receive and queued-response
cancellation. Its assertions are also unexecuted under the build hold.

## Restart while the HUD remains visible

1. Use long player/opponent names, then restart during an LP change and during a
   human prompt. Repeat with different starting LP and deck selections.
2. Break inside the worker's initialization block that replaces `strLP`, `selfnames`,
   `opponames` and active field vertices. Continue the GUI thread: it must not enter
   the drawing section until the worker releases `gMutex`.
3. Resume both threads. LP/name text must remain complete and the new duel must reach
   a playable prompt. No old selection or response may be carried into the new duel.
4. Exercise a puzzle `MSG_AI_NAME` while its HUD is visible; changing the opponent
   name must use the same render mutex.

## Natural win and immediate next match

Win once as each side, including deck-out. After the result animation, verify the
offline menu returns, Start is enabled, portraits are cleared and the previous worker
finishes. Start another match immediately and verify its first human choice is accepted.
