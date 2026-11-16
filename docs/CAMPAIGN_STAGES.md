# Campaign stage portrait contract

The native Campaign shell consumes `config/campaign-stages.json` from the generated `Bundle/game` payload. The file is generated from the root-controlled `YuGiOhNativeIOS/GeneratedData/campaign-stages.json` by `tools/prepare_edopro_assets.py`; it is not read from the `NativeClient/distribution` submodule at runtime.

Schema version `1` contains a `stages` array. Each record has:

- `id`: contiguous integer starting at 1.
- `chapter` and `node`: positive map coordinates.
- `title`: unique display label.
- `deckKey`: key from `config/duel-portraits.json`.
- `icon`: safe PNG basename matching that portrait catalog entry.
- `unlockAfterWins`: non-negative monotonic unlock threshold.

The native loader must treat missing/invalid files as a safe fallback: show a neutral stage icon and keep the existing duel-deck selector usable. It must reject path traversal, absolute paths, and icons that do not match the portrait catalog. Portrait files stay under `textures/portraits/` and are copied by the existing manifest-verified resource pipeline.

Validate before any native build:

```powershell
python tools/verify_campaign_stages.py `
  --stages YuGiOhNativeIOS/GeneratedData/campaign-stages.json `
  --portrait-catalog outputs/edopro-game-v12-final/config/duel-portraits.json `
  --portrait-root outputs/edopro-game-v12-final/textures/portraits
```
