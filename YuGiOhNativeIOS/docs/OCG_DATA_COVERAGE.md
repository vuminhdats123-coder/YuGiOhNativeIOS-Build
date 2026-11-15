# Đối chiếu dữ liệu OBB với Project Ignis

Kết quả này chứng minh mức phủ dữ liệu và đường dẫn script ở hai snapshot cụ
thể. Nó chưa chứng minh engine EDOPro chạy được trong iOS hoặc tái tạo đúng
hành vi của APK. Không build, không chạy Lua/Swift/OCGCore trong bước này.

## Nguồn đã pin

- [ProjectIgnis/BabelCDB](https://github.com/ProjectIgnis/BabelCDB/tree/6e21009855ed5f3b5966a24545bd0db393d44697),
  commit `6e21009855ed5f3b5966a24545bd0db393d44697`, file English `cards.cdb`:
  14.794 records joined `datas`/`texts`, SQLite integrity check đạt.
- [ProjectIgnis/CardScripts](https://github.com/ProjectIgnis/CardScripts/tree/14f3b8905ff95a8f869fd6891aec4d6b580db1e1),
  commit `14f3b8905ff95a8f869fd6891aec4d6b580db1e1`.
- OBB SHA-256:
  `7ad6962f99ec019a57e2324f0dab23fbbdee81669ed2d2fb766706eaf05a756b`.

Binary database và toàn bộ archive script tham chiếu nằm trong
`outputs/ocg-reference/`, không đưa vào Git. Không sửa APK/OBB hoặc catalog
GeneratedData đã có. Audit đọc SQLite ở chế độ read-only và so sánh Prop,
Pass, tên/mô tả, các YDC với raw OBB trước khi xuất bridge.

## Kết quả phủ

| Hạng mục | Kết quả |
|---|---:|
| Thẻ OBB có dữ liệu | 7.580 |
| Password khác 0 | 7.479, tất cả unique và có `datas.id` tương ứng |
| Tên tiếng Anh khớp nguyên văn | 7.462 / 7.479 |
| Tên đổi cách viết/tên mới | 17 |
| Khác ATK/DEF/level trong nhóm password khác 0 | 0 |
| Mô tả khác sau chuẩn hóa whitespace | 2.728 |
| Có script `official/c<password>.lua` trực tiếp | 6.838 |
| Normal/Normal Tuner không cần script riêng | 640 |
| Script ngoài official được duyệt riêng | 1: Red-Eyes Darkness Metal Dragon trong pre-errata |
| Ảnh OBB ánh xạ bằng password nguồn | 7.479, không ảnh thiếu |
| Mapping ảnh sau 7 remap đã duyệt | 7.486, trong đó 2 ID không có ảnh OBB |
| YDC byte-identical với OBB | 799 / 799 |
| Deck có toàn bộ ID ánh xạ bằng password nguồn | 784 / 799 |
| Konami ID trong deck ánh xạ bằng password | 5.208 / 5.215 |
| Deck sau remap được duyệt | 799 / 799; 5.215 / 5.215 ID |

Tên đổi gồm những trường hợp như Red-Eyes B. Dragon → Red-Eyes Black Dragon.
Không coi 2.728 khác biệt mô tả là 2.728 errata: có thay đổi định dạng, thuật ngữ
và câu chữ. Script/database hiện hành áp dụng luật Project Ignis tại snapshot,
không đảm bảo giữ nguyên luật/errata của Duel Generation cũ.

## Mapping được duyệt riêng

101 record OBB có password 0: 96 token và 5 lá thần. Code 0 không đại diện cho
tất cả những lá này. Tokens của OCGCore có code do script tạo, một tên có thể
có nhiều token hoặc alternate artwork, đôi khi thông số được tính lúc tạo.
Audit xuất các candidate token trùng tên chính xác nhưng **không tự nhận là
mapping**. 96 token này không xuất hiện trực tiếp trong 799 deck.

Trong 799 deck có bảy ID phải xét riêng:

| Konami ID | Tên | Candidate canonical trong BabelCDB | Lý do không lấy trực tiếp |
|---|---|---:|---|
| 4998 | Obelisk the Tormentor | 10000000 | Password OBB = 0 |
| 4999 | Slifer the Sky Dragon | 10000020 | Password OBB = 0 |
| 5000 | The Winged Dragon of Ra | 10000010 | Password OBB = 0 |
| 11927 | The Winged Dragon of Ra - Sphere Mode | 10000080 | Password OBB = 0 |
| 12234 | The Winged Dragon of Ra - Immortal Phoenix | 10000090 | Password OBB = 0 |
| 10855 | Number 94: Crystalzero | 62070231 | Không có definition trong OBB |
| 11766 | Number S39: Utopia the Lightning | 56832966 | Không có definition trong OBB |

Bảy mapping trên đã được duyệt riêng theo hướng kết hợp EDOPro + OBB. Tool
khóa rõ từng cặp ID, yêu cầu tên exact và `alias=0` duy nhất, kiểm tra type,
ATK/DEF/level của CDB. Với năm lá thần còn đối chiếu stats/kind và password 0
trong raw OBB. Với hai lá không có definition, report ghi
`nativeDataMissing: true`, không tạo Prop giả cho OBB. Nhờ đó 15 deck còn thiếu
được chuyển đủ nhưng vẫn phân biệt ánh xạ bằng password với remap đã xét duyệt.

Năm ảnh lá thần có trong OBB; ảnh `10855.jpg` và `11766.jpg` không có.
Hai hàng ảnh này giữ `obbPath: null` để builder báo thiếu hoặc dùng placeholder,
không mượn ảnh một card khác.

Đối chiếu cũng phát hiện nhãn race trong JSON cũ của năm lá thần sai: raw
`raceCode=23` từng được gán nhãn Cyberse từ enum của phiên bản game mới hơn.
Đó không phải nội dung đúng của các lá thần. Audit không sửa OBB/catalog; engine
EDOPro phải dùng race bitmask của CDB. Số khác biệt stats bằng 0 ở trên chỉ xét
ATK/DEF/level của nhóm password khác 0, không khẳng định mọi enum nguồn đã đúng.

Các alias trong CDB có thể là quy tắc "same name", không chỉ alternate art.
Ví dụ Harpie Lady 1 vẫn giữ code/script riêng dù có alias Harpie Lady. Bridge
giữ nguyên password của card, không gộp mọi alias về một script.

## Script và thư viện phụ thuộc

Một Effect Monster, Red-Eyes Darkness Metal Dragon (`88264978`), thiếu file
`official/c88264978.lua` tại snapshot này; có file cùng tên dưới `pre-errata/`.
Một override đúng code này đã được duyệt: `88264978` →
`pre-errata/c88264978.lua`. Report lưu đường dẫn/hash và lưu ý era. Đây không
phải luật chọn mọi file pre-errata khi official thiếu; không đổi code sang một
lá ngẫu nhiên hoặc ghi đè toàn bộ official bằng thư mục pre-errata.

640 lá scriptless chỉ là Plain Normal/Normal Tuner (`type` 0x11/0x1011).
Fusion/Synchro không effect vẫn cần script triệu hồi: Flame Swordsman và Gaia
Knight đều có script. Vì vậy không thể bỏ script chỉ vì card không có effect.

Đối chiếu tĩnh bắt đầu từ 25 thư viện Lua ở root và các official scripts của
những password đã khớp cùng bảy remap và override đã duyệt; số file closure
chính xác được ghi trong report. Có 24 lệnh load literal và bốn biểu thức load
động trong `utility.lua`. Những biểu thức này và API core
chưa chạy. Full archive giữ nguyên `official/`, `pre-errata/`, `unofficial/`
và những thư mục khác; không làm phẳng rồi ghi đè các file trùng tên.

README của CardScripts xác định Lua 5.3 và core `edo9300/ygopro-core`. Chọn
snapshot client/core tương thích vẫn là bước độc lập; không ghép script mới với
core cũ rồi mặc nhiên coi hoạt động đúng.

## Giấy phép

[README/COPYING của CardScripts](https://github.com/ProjectIgnis/CardScripts/blob/14f3b8905ff95a8f869fd6891aec4d6b580db1e1/README.md)
ghi **AGPL-3.0-or-later**. Report lưu hash của COPYING. Metadata/root README của
BabelCDB được kiểm tra không có giấy phép riêng rõ ràng; chưa kết luận điều kiện
phân phối lại database. Dữ liệu/art gốc OBB vẫn là nguồn riêng của người dùng,
không được bao phủ chỉ vì script có giấy phép mã nguồn mở.

## Cách chạy và bridge schema

```powershell
python YuGiOhNativeIOS/Tools/audit_ocg_coverage.py --fetch
```

Không có `--fetch`, tool chỉ đọc những reference đã tải, xác nhận SHA-256 và
ghi `GeneratedData/ocg-coverage.json`. Đường dẫn được tính từ script, không
phụ thuộc thư mục hiện hành. Không có lệnh build hoặc GitHub Actions.

Report chứa dữ liệu dùng cho bước đóng gói sau:

- `sources`: repo/commit/URL/hash của OBB, database và archive script.
- `bridge.konamiToCoreCode`: các password khác 0 đã chứng minh trong database
  cộng bảy mapping trong `bridge.reviewedRemaps` có provenance rõ ràng.
- `bridge.deckMappings`: cả ba nhóm Konami ID nguồn và code core song song;
  code chưa giải được giữ `null`, có zone/index/reason trong `unresolved`.
- `bridge.imageMappings`: đường dẫn JPG trong OBB, tên file theo core code,
  kích thước và CRC32; chưa sao chép hoặc sửa ảnh.
- `bridge.unresolved`: 96 token password 0, kèm candidate,
  `automaticMappingAccepted: false`; chúng không có trong deck cần chuyển.
- `bridge.scriptOverrides`: override duy nhất của Red-Eyes Darkness Metal
  Dragon. Builder cần hỗ trợ đúng lookup này và giữ cây thư mục script.
- `missingOfficialScripts`, `scriptDependencies`, `metadataDifferences` và
  `aliases`: bằng chứng để xử lý khác biệt trước khi đưa runtime vào app.

`auditCompleted: true` chỉ có nghĩa audit đã chạy. `runtimeVerified`, `built`
và `fullGameReady` đều giữ `false`.

## Bản tiếng Việt tùy chọn từ OBB

Trong bản OBB người dùng cung cấp, `CARD_Desc_I.bin` chứa mô tả tiếng Việt,
không phải tiếng Ý như tên slot I thường gợi ý. `CARD_Name_I.bin` giữ tên thẻ
từ nguồn, phần lớn là tiếng Anh. Công cụ `tools/create_obb_locale.py` dùng cặp
offset tên/mô tả của slot I để tạo:

```text
config/languages/vi-obb/obb-vi.cdb
config/languages/vi-obb/locale-report.json
```

Database locale chỉ có bảng `texts` (`id`, `name`, `desc`, `str1`…`str16`),
**không có bảng `datas`**. Tên/mô tả dùng text nguồn I; cả 16 chuỗi lựa chọn
hiệu ứng giữ nguyên giá trị tiếng Anh của CDB hiện hành, kể cả null. Vì vậy
locale không thay ATK/DEF, loại thẻ, mã effect hoặc những metadata khác.

Kết quả dữ liệu thật: 7.484 hàng localized, không có tên/mô tả nguồn rỗng;
96 token chưa có mapping không đưa vào locale, hai ID không có definition OBB
`10855`/`11766` tiếp tục dùng text tiếng Anh của database chính.
SQLite integrity check đạt và hash hai đầu vào không đổi. SHA-256 locale:
`62735d91714fe5415f37c6084ba49d3eec38e2ccdfefd862db024c95c8b192cf`.

EDOPro ở commit đã pin tìm locale dưới `config/languages/` và đọc các `.cdb`
bằng parser chỉ chọn bảng texts: [Game::ApplyLocale](https://github.com/edo9300/edopro/blob/d0f111d6f3e0d4ee529b88a869ae0a971954bae3/gframe/game.cpp#L3994),
[DataManager::ParseLocaleDB](https://github.com/edo9300/edopro/blob/d0f111d6f3e0d4ee529b88a869ae0a971954bae3/gframe/data_manager.cpp#L180).
Generator không đổi locale mặc định tiếng Anh. Chọn `vi-obb` chỉ thay text
card được cung cấp, không dịch toàn bộ giao diện hoặc mọi prompt.

Đây là bản dịch legacy đi cùng OBB; một số mô tả có thể khác effect/errata của
engine EDOPro hiện hành. Không ghi đè CDB chính hoặc quảng bá đây là bản dịch
đã cập nhật đầy đủ theo luật mới.

Sáu kiểm tra Python cho offset UTF-16, bounds, texts-only, prompt retention,
input immutability, output determinism, audit identity và chống ghi đè đã đạt:

```powershell
python -m unittest discover -s tests -p test_obb_locale.py -v
```

Những kiểm tra trên không chạy ứng dụng, Lua/core, Swift hoặc build.
