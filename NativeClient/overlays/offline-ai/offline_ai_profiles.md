# Offline AI grounded profiles

The policy in `offline_ai.js` only gives special treatment to cards in the table below. The IDs
are the filenames in the pinned `outputs/edopro-game-v9/script/official` corpus, and each role was
checked against that card script. Cards outside these profiles use the conservative unknown-effect
fallback when a live board snapshot is present.

| Role | Profiles (Konami ID) |
| --- | --- |
| Board removal | Dark Hole `53129443`, Raigeki `12580477`, Mystical Space Typhoon `5318639`, Fissure `66788016`, Smashing Ground `97169186`, Bottomless Trap Hole `29401950`, Torrential Tribute `53582587`, Compulsory Evacuation Device `94192409`, Dimensional Prison `70342110`, Dust Tornado `60082869`, Raigeki Break `4178474` |
| Negation / protection | Solemn Judgment `41420027`, Magic Jammer `77414722`, Solemn Strike `40605147`, Solemn Warning `84749824`, Effect Veiler `97268402`, Ash Blossom & Joyous Spring `14558127`, Forbidden Chalice `25789292`, Mirror Force `44095762`, Negate Attack `14315573`, Book of Moon `14087893`, Rush Recklessly `70046172` |
| Revive / grave setup | Monster Reborn `83764718`, Monster Reincarnation `74848038`, Premature Burial `70828912`, Call of the Haunted `97077563`, Silver's Cry `87025064`, Foolish Burial `81439173`, Foolish Burial Goods `35726888` |
| Draw / search | Pot of Greed `55144522`, Graceful Charity `79571449`, Upstart Goblin `70368879`, Pot of Duality `98645731`, Trade-In `38120068`, Reinforcement of the Army `32807846`, One for One `2295440`, The Melody of Awakening Dragon `48800175` |
| Ritual / extra summon | Black Luster Ritual `55761792`, Gishki Aquamirror `46159582`, Polymerization `24094653`, Knightmare Phoenix `2857636`, Gagaga Cowboy `12014404`, Cyber Dragon Nova `58069384`, Cyber Dragon Infinity `10443957`, Junk Warrior `60800381`, Junk Synchron `63977008`, Scrap Warrior `42711820`, Junk Gardna `37993923`, Junk Destroyer `74860293`, Junk Berserker `59771339` |
| Known monsters used for value / combo tests | Blue-Eyes White Dragon `89631139`, Blue-Eyes Alternative White Dragon `38517737`, Cyber Dragon `70095154`, Cyber Dragon Core `23893227`, D.D. Warrior Lady `7572887`, Tremendous Fire `46918794` |

The combo rules are deliberately bounded by the current snapshot. They can chain an own-hand
Foolish Burial into an own-Grave Monster Reborn target, use Trade-In only when a current Level 8
discard exists, revive a public normal Dragon with Silver's Cry, and choose Junk Synchron/Junk
Warrior only when the current own Grave/Extra contains the required pieces. The policy never reads
Main Deck identities or order and never predicts a future draw.
