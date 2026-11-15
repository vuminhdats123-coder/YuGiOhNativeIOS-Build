# Native EDOPro client

Hướng port hiện tại là dùng client EDOPro native cùng ocgcore và bộ script thẻ hoàn chỉnh, sau đó chuyển tài nguyên phù hợp từ OBB sang định dạng client này. `YuGiOhNativeIOS/` vẫn là prototype tham chiếu; engine Swift giới hạn trước đó không được coi là engine của bản port hoàn chỉnh.

## Source đã chọn

- Client: [`edo9300/edopro`](https://github.com/edo9300/edopro), commit `d0f111d6f3e0d4ee529b88a869ae0a971954bae3`, tại `NativeClient/edopro`.
- Core tương ứng với submodule của client: [`edo9300/ygopro-core`](https://github.com/edo9300/ygopro-core), commit `46779fbe40e6a9bd8967f5dc6a03f4eaa6550d57`, C API 11.0.
- Lua tương ứng với core: [`lua/lua`](https://github.com/lua/lua), commit `6e22fedb74cf0c9b6656e9fce8b7331db847c605`, Lua 5.4.8.

Giữ nguyên các pin này khi chuẩn bị source. Không tự thay core bằng HEAD mới hơn của repository khác: API, protocol và bộ script phải được kiểm tra cùng nhau.

`NativeClient/distribution` khóa ở `54a6e2395c532648ff762540e9615319fac4f51b`, chỉ dùng
tài nguyên giao diện/font/config. Script và database được chuẩn bị riêng theo lock,
không dùng các gitlink lồng nhau của Distribution.

## Tích hợp đã chuẩn bị

```powershell
python tools/apply_native_patches.py
python tools/check_native_port.py
```

Patch đầu tiên khởi tạo `Bundle/game` vào `Documents/EDOPro` trước khi client chạy.
Copy lần đầu đi qua staging rồi đổi tên; dữ liệu người dùng đã có không bị ghi đè.
Hiện nâng cấp giữa hai manifest khác nhau sẽ dừng và giữ nguyên dữ liệu cũ; cần
làm migration trước khi phát hành bản nâng cấp cho người dùng.

`tools/prepare_edopro_assets.py` nhận OBB, CDB, CardScripts ZIP, Distribution và
báo cáo `ocg-coverage.json`; xuất thư mục dữ liệu mới với `package-manifest.json`.
Nó không biên dịch game. Gói đã chuẩn bị tại `outputs/edopro-game-v3`: 46.058 file,
420.250.449 byte chưa tính manifest, gồm mô-đun AI đã kiểm thử. Xem [runtime-package-summary.json](runtime-package-summary.json)
để đối chiếu checksum và số lượng. Gói hiện nằm trên máy này, không được đưa vào Git.

Tạo lại từ source và các archive đã pin (chọn thư mục output mới nếu đã tồn tại):

```powershell
python tools/prepare_edopro_assets.py --obb com.konami.ygodgtest/main.116.com.konami.ygodgtest.obb --cdb outputs/ocg-reference/BabelCDB-6e21009855ed5f3b5966a24545bd0db393d44697-cards.cdb --scripts outputs/ocg-reference/CardScripts-14f3b8905ff95a8f869fd6891aec4d6b580db1e1.zip --base-assets NativeClient/distribution --audit YuGiOhNativeIOS/GeneratedData/ocg-coverage.json --source-lock NativeClient/upstream.lock.json --include-vi --out outputs/edopro-game-v3
```

799 deck đã đổi ID đầy đủ. 651 deck đạt kiểm tra kích thước, vị trí Main/Extra và
giới hạn ba bản sao; 148 danh sách còn lại được lưu trong `converted-decks` với lý do
trong `reports/decks.json`. Đây chưa phải kiểm tra banlist hay chứng minh đấu được.
7.714 JPG và 134 MP3 được giữ lại; 7.484 ảnh đã ánh xạ sang passcode và 15 bản nhạc
đã đặt vào thư mục BGM. Locale tùy chọn có 7.484 mô tả tiếng Việt, chỉ bảng `texts`.

Xcode đã có bước copy toàn bộ thư mục thành `Bundle/game`, kiểm tra từng SHA256
và giữ nguyên cấu trúc. Bước copy đã chạy với toàn bộ payload trong một thư mục
fixture: 46.058 file và 17 icon được chép đúng. Fixture chỉ có tài nguyên, không
có executable và không phải một ứng dụng cài được.

Ảnh OBB là artwork hình vuông, không phải mặt lá bài đầy đủ. Compositor iOS mới
dùng CoreGraphics/CoreText để vẽ khung, tên, thuộc tính, Level/Rank, type, mô tả,
ATK/DEF, scale Pendulum và mũi tên Link. Ảnh thiếu được thay bằng ô thông báo và
thông tin thẻ. Text quá dài có dấu rút gọn; nội dung đầy đủ vẫn ở bảng thông tin.
Metadata được chụp trước khi đưa vào hàng đợi; worker chỉ tạo ảnh CPU, còn GPU
vẫn do luồng render hiện có cập nhật. Chưa chạy renderer trên iOS.

Bản dịch tiếng Việt trong `CARD_Desc_I` là bản của OBB cũ, được giữ thành
locale tùy chọn; thông số/luật vẫn do database và script EDOPro quyết định.

## Có thể dùng lại trực tiếp

Client đã có bàn đấu, bộ chọn bài/vị trí/chain, trình sửa deck, đọc CDB và xử lý thông điệp từ engine; mã iOS nằm trong `gframe/iOS/`. Target Premake `ygopro` liên kết core tĩnh; phù hợp làm điểm xuất phát cho bản iPhone. Target `ygoprodll` dùng cơ chế nạp core riêng và không phải lựa chọn mặc định của bản tích hợp này.

Ảnh OBB được đặt tên theo Konami ID, còn EDOPro dùng card code/passcode. Phải ánh xạ chính xác trước khi xuất `pics/<code>.jpg`. `.ydc` cũng phải đổi ID trước khi tạo `.ydk`. Không đưa trực tiếp `.bin` của Konami vào callback dữ liệu ocgcore: loại thẻ, archetype/setcode và alias có encoding khác.

## Trạng thái kiểm chứng

Đã sinh cấu hình Xcode bằng Premake 5.0.0 trên Windows để kiểm tra cấu trúc.
Các đường dẫn Windows trong project này phải được sinh lại trên runner macOS.
Chưa chạy compiler, Xcode, simulator, GitHub Actions hoặc ký IPA cho client mới.
Sinh project và kiểm thử dữ liệu không chứng minh ứng dụng đã chạy trên thiết bị.

Chi tiết dependency, bootstrap tài nguyên, cấu hình Xcode và các bước kiểm tra còn lại ở [EDOPRO_INTEGRATION.md](../docs/EDOPRO_INTEGRATION.md).

Menu `Offline vs AI` chọn riêng deck người chơi và đối thủ; source tạo hai team
OCG, trộn Main Deck độc lập và dùng MR5, 8.000 LP. Người chơi trả lời prompt bằng
GUI; AI chỉ trả lời player 1 bằng JavaScriptCore. Cùng mô-đun JS được kiểm thử bằng
Node cho 21 nhóm prompt, chain, nguyên liệu, thông tin ẩn và đầu vào lỗi. Không dùng
`DUEL_SIMPLE_AI`, không cần WindBot hoặc mạng. Lỗi protocol dừng rõ ràng, không tự
gửi lại vô hạn. Đây là AI heuristic cơ bản có giới hạn tìm kiếm, chưa được kiểm
chứng bằng một trận native; lưu replay offline đang tắt.

```powershell
python -m unittest discover -s tests -v
node NativeClient/overlays/offline-ai/offline_ai.test.js
python NativeClient/overlays/card-renderer/verify_renderer_contract.py
python tools/apply_native_patches.py --check
python tools/check_native_port.py
```

Kiểm tra hiện tại tách biệt JS/protocol, bố cục/dữ liệu và native runtime. Các kiểm
tra PNG, Unicode, hướng ảnh và luồng của compositor được viết trong
`overlays/card-renderer/tests/card_face_native_checks.mm` nhưng chưa chạy.

Client và core theo AGPL-3.0-or-later; Lua theo MIT. Giữ thông báo bản quyền và giấy phép nguồn/dependency khi đóng gói. Tài nguyên và script có giấy phép riêng; không đổi quyền của tài nguyên OBB.
