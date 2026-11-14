# Full OBB extraction

Run from the repository root:

```powershell
python YuGiOhNativeIOS/Tools/extract_obb.py .\com.konami.ygodgtest\main.116.com.konami.ygodgtest.obb .\YuGiOhNativeIOS\GeneratedData
```

This creates a complete file manifest, decoded English card names/descriptions, and copies the remaining card index tables for later format-specific parsing. It does not decode proprietary `.ydc` or native engine formats.
