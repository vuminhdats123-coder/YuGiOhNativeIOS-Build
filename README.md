# YuGiOhNativeIOS — native game integration

Hướng chính hiện dùng **client EDOPro native + ocgcore + Lua card scripts**, kết hợp
ảnh, deck và tài nguyên phù hợp từ APK/OBB người dùng cung cấp. Không tiếp tục mở rộng
engine Swift giới hạn bằng cách viết tay từng effect.

- `NativeClient/edopro`: source client iOS có bàn đấu, prompts, deck editor và core.
- `NativeClient/distribution`: tài nguyên giao diện/font/config upstream.
- `NativeClient/upstream.lock.json`: phiên bản client/core/Lua/database/scripts đã chốt.
- `YuGiOhNativeIOS/`: prototype Swift và công cụ đọc OBB giữ lại để đối chiếu.
- `tools/`: chuẩn bị tài nguyên và kiểm tra tích hợp native, không tự build.

`cards.cdb` và Lua scripts quyết định luật/hiệu ứng. Ảnh OBB được đổi từ Konami ID
sang passcode; deck YDC được đổi sang YDK qua bảng ánh xạ có kiểm chứng. Không ghi
đè database EDOPro bằng bitfield Konami hoặc coi tên thẻ bổ sung là effect đã hoạt động.

## Chuẩn bị source

```powershell
git submodule update --init NativeClient/edopro NativeClient/distribution
git -C NativeClient/edopro submodule update --init --recursive
python tools/apply_native_patches.py
python YuGiOhNativeIOS/Tools/audit_ocg_coverage.py --fetch
```

Với Windows và đường dẫn dài, bật `core.longpaths` riêng cho checkout cần thiết.
Các submodule `script`/`expansions` của Distribution không dùng: data được chuẩn bị
theo các pin trong `upstream.lock.json`.

Lệnh audit tải database/script theo revision đã khóa và đối chiếu OBB nguồn;
recipe đóng gói ảnh, deck, âm thanh và tiếng Việt nằm trong `NativeClient/README.md`.
Các file đầu ra lớn được giữ ngoài Git; báo cáo và công cụ tái tạo được lưu trong repo.

Xem [NativeClient/README.md](NativeClient/README.md) và
[docs/EDOPRO_INTEGRATION.md](docs/EDOPRO_INTEGRATION.md) cho kiến trúc và phần còn thiếu.

## Build đang hoãn

Chưa chạy compiler, Xcode hoặc GitHub Actions. Workflow cũ tạo IPA prototype đã được
lưu làm tham chiếu ở `NativeClient/legacy/`; workflow hiện tại chỉ là preflight thủ công
và không tạo IPA. `NativeClient/port-status.json` giữ `fullGameReady=false` cho đến khi
khởi tạo tài nguyên, đấu thật, offline AI và thao tác iPhone được kiểm chứng.

Mã nguồn hiện có menu chọn hai deck và đấu offline bằng OCG core. AI dùng mô-đun
JavaScript chạy trong JavaScriptCore của iOS; cùng mô-đun được kiểm thử bằng Node.
Mặt thẻ được ghép bằng CoreGraphics/CoreText từ tranh OBB và thông tin database,
có phương án hiển thị khi thiếu tranh. AI v8 dùng thế trận công khai và 22 profile hiệu ứng để chọn nước đi, không nhận
thứ tự deck, seed hoặc lá rút kế tiếp. Thông tin bài kín được che trước khi vào
phần ra quyết định; xem [AI_TACTICS.md](NativeClient/AI_TACTICS.md).

Kiểm tra core Windows đã hoàn tất [36 ván với AI v8](NativeClient/HOST_VALIDATION_V8.md),
[14 ca chiến thuật/chain/Damage Step](NativeClient/HOST_TACTICAL_VALIDATION.md) và
36 ca scenario hồi quy, không retry/lỗi Lua. Kiểm tra khởi tạo lịch sử bao phủ
7.486 mã thẻ; database/script hiện vẫn giữ nguyên. Các ca kiểm tra có phạm vi cụ
thể, chưa chứng minh AI chơi tối ưu mọi thẻ hoặc mọi combo.
Ứng dụng, hình ảnh và thao tác trên iPhone vẫn chưa được chạy/kiểm chứng.

Tham chiếu giao diện từ video người dùng và phạm vi áp dụng được ghi trong
[DUEL_GENERATION_UI_REFERENCE.md](docs/DUEL_GENERATION_UI_REFERENCE.md).
Payload v8 giữ ảnh gốc và chân dung NPC đã đối chiếu. Mã iOS đã có bàn đấu giữa,
thông tin thẻ trái, LP/chân dung phải, bảng chọn 5×3 và vùng an toàn UIKit.
Thanh phase được đặt dưới tay bài để giữ ô Extra của MR5. Đây là triển khai
nguồn; giao diện và cảm ứng trên iPhone vẫn chưa được chạy/kiểm chứng.

Recipe Xcode, dependency iPhoneOS đã kiểm tra và bước copy toàn bộ `Bundle/game`
nằm trong [NativeClient/iOS/README.md](NativeClient/iOS/README.md). Project sinh
trên Windows chỉ phục vụ kiểm tra cấu trúc; phải sinh lại trên runner macOS với
đường dẫn của runner. Không đưa project có đường dẫn Windows vào build trên Mac.

Combo evidence passes 6/6 for Foolish Burial→Monster Reborn, Trade-In→Silver's Cry and ROTA→Junk Synchron search/summon; the third Synchro step remains unproven. Two Knightmare Phoenix regression cases remain documented gaps.
