# OBB Recipe and Shop audit

The source OBB is a ZIP archive with 10,747 members. Its deck editor and shop
data are present as real plist catalogs, not only UI strings.

## Recipe catalogs

- `assets/IAP_YDC_DECK.plist`: 58 entries, `recipe_id` 1–58. Every referenced
  `MD_Deck*.ydc` file exists.
- `assets/YGOPOINTS_DECKS.plist`: 8 free entries, `recipe_id` 59–66. Every
  referenced `Free_*.ydc` file exists.
- `assets/DeckEditOverlay_en.plist`: New, Revert, Recipe, Save As and the
  unsaved-change prompts.
- `assets/DeckEditCommonOverlay_en.plist`: Add Recipe, all/unlocked recipes,
  favorites and recipe list labels.

The asset preparation tool now emits `config/recipe-catalog.json` with
`recipe_id`, `ydc`, `locNames`, `locDesc`, availability and the missing-file
list. The current Deck Editor already has the real New/Revert actions, but it
does not yet expose this recipe catalog.

## Shop catalogs

- `assets/IAP_YDC_PACK.plist`: 80 pack entries; 79 referenced `.ydc` files are
  present. `MD_Pack06_Neo-Spacian.ydc` is the only missing reference.
- `assets/IAP_YDC_SUPPORT.plist`: 76 support entries; all referenced files are
  present.
- `assets/Shop_en.plist`, `ShopPagePremium_en.plist`,
  `ShopPageYgoPoints_en.plist`, `ShopManager_en.plist`,
  `ShopCardList_en.plist`, `ShopCardsCommon_en.plist` and
  `STORE_ITEM_LOCALIZATION_en.plist` provide the shop labels and item text.
- `assets/YGOPOINTS_DECKS.plist` and `assets/YGOPOINTS_BOOSTERS.plist`
  describe Duel Point exchanges. `btn_shop.png`, `points.png` and
  `sp_box_points.png` provide the shop visuals.

The catalogs support an offline browse/preview/exchange screen. Purchase,
restore and account ownership are server/IAP semantics and cannot be recreated
from OBB data alone. The missing Neo-Spacian pack must remain marked unavailable
until its deck file is recovered or the item is hidden.
