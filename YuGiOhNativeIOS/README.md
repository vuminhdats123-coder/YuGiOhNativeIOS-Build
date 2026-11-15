# YuGiOhNativeIOS

Project native SwiftUI nội bộ, dùng dữ liệu tên và mô tả thẻ đã trích xuất từ OBB thành `Resources/cards_en.json` (7,580 mục). Có tìm kiếm, lọc và xem chi tiết offline.

## Duel offline và kiểm tra

Lõi `DuelState.swift` hỗ trợ một tập luật luyện tập với AI hoặc hai người trên cùng máy.
AI chọn hành động qua cùng API luật, không nhận danh tính bài trên tay/bài úp của đối phương.
Các cửa sổ phản hồi khi triệu hồi, tấn công và chuyển phase được xử lý trước khi
áp dụng kết quả; MST/Mirror Force/Solemn Judgment dùng đúng loại cửa sổ được hỗ trợ.
Damage Step có năm bước riêng và có chọn lại mục tiêu tấn công. Bộ luyện tập
thêm Kuriboh, Cyber Dragon, Tune Warrior cùng Flame Swordsman (Fusion) và
Gaia Knight (Synchro) trong Extra Deck. Đây vẫn là tập luật giới hạn, chưa phải
toàn bộ engine hoặc toàn bộ effect của bản Android.
Chi tiết phạm vi và giới hạn ở [docs/OFFLINE_DUEL.md](docs/OFFLINE_DUEL.md).
Các deck YDC gốc vẫn dùng để tra cứu; không mặc định chơi được mọi effect trong đó.

Chạy kiểm tra dữ liệu offline từ repository root:

```powershell
python YuGiOhNativeIOS/Tools/verify_duel_data.py
python YuGiOhNativeIOS/Tools/port_readiness.py
```

Self-check hành vi Swift ở `Tests/duel_state_checks.swift` và `Tests/duel_ai_checks.swift`
đã được viết nhưng chưa chạy.
Không đánh đồng các kiểm tra dữ liệu Python với kết quả chạy engine.

## Build hiện đang hoãn

Theo yêu cầu của người dùng: chưa build app, IPA hoặc chạy GitHub Actions cho tới khi được phép.
Workflow chỉ có `workflow_dispatch`; push không tự build. Khi được phép, workflow macOS 15
sẽ archive cho iPhone (`iphoneos`) và tạo artifact `YuGiOhNativeIOS-unsigned-ipa`.
Không sử dụng certificate hoặc provisioning profile. IPA phải được ký trước khi cài.
