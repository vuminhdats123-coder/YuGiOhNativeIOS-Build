# Current Extra Deck regression

With runtime v9a and the current tactical AI, the canonical Extra Deck suite passes **10/10 scenarios** from both perspectives: Synchro trigger, Xyz detach, Knightmare Phoenix discard/destroy, Solemn Judgment summon negation and Link Rating material. The core accepted every response with zero retries or Lua/core errors.

This current report is `host-extra-deck-validation-v9-final.json`; the earlier 8/10 diagnostic was caused by the previous runtime/AI profile and is not the current result.

This remains Windows precompiled-core evidence. Native iOS UI, Objective-C++ bridge, touch and device lifecycle are unverified; no compiler, Xcode, Actions or IPA build was run.
