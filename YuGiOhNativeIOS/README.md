# YuGiOhNativeIOS

Project native SwiftUI nội bộ, dùng dữ liệu tên và mô tả thẻ đã trích xuất từ OBB thành `Resources/cards_en.json` (7,580 mục). Có tìm kiếm, lọc và xem chi tiết offline.

## Build bằng GitHub Actions

1. Tạo repository GitHub và đẩy toàn bộ thư mục này lên nhánh `main`.
2. Vào tab **Actions** → workflow **iOS Build**.
3. Chạy **Run workflow** hoặc push commit mới.
4. Tải artifact `YuGiOhNativeIOS-simulator`.

Workflow dùng macOS 14 runner, build unsigned cho simulator. Để cài lên iPhone cần signing certificate/provisioning profile hoặc secrets của Apple Developer.
