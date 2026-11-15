# Tham chiếu giao diện Duel Generation

Nguồn người dùng cung cấp: [video của Tray Trần](https://www.youtube.com/watch?v=a1tYUTDbrcY),
quan sát ngày 2026-11-15. Các ghi chú dưới đây dựa trên những đoạn đã mở trực tiếp
trong trình duyệt, không phải bản chép lời hay kết quả chạy ứng dụng iOS.

## Những gì đã thấy

| Đoạn video | Bố cục/thao tác quan sát được | Hướng áp dụng |
|---|---|---|
| [6:30](https://www.youtube.com/watch?v=a1tYUTDbrcY&t=390s) | Menu dọc, nút xanh cyan, nền lưới/mạch điện, hai lá bài lớn hai bên. | Giữ phong cách tài nguyên gốc; không thêm các nút chức năng chưa có backend. |
| [7:00](https://www.youtube.com/watch?v=a1tYUTDbrcY&t=420s) | Màn chọn đối thủ có chân dung, liên kết và tiến độ trên nền mạch điện xanh/tím. | Là tham chiếu cho phần chọn đối thủ; chưa triển khai campaign/tiến độ giả. |
| [8:00](https://www.youtube.com/watch?v=a1tYUTDbrcY&t=480s) | Thẻ và mô tả ở trái; bảng chọn thẻ giữa màn hình có 5 cột, thanh cuộn, số lượng cần chọn và nút Xong. | Tách rõ xem thông tin, chọn thẻ và xác nhận; giữ kiểm tra số lượng của engine. |
| [Khoảng 9:00](https://www.youtube.com/watch?v=a1tYUTDbrcY&t=540s) | Bàn đấu nhìn từ trên; tay bài phía dưới, phase ở giữa, LP/chân dung đối thủ và người chơi ở phải. Menu hành động nổi có Xem/Kích hoạt. | Bố cục iOS ba vùng và phép chiếu/hit-testing dùng chung; phase đặt ở footer để giữ ô Extra Monster của MR5. |

Các sửa đổi luật/Exodia trong tiêu đề video không được coi là yêu cầu thay luật của
bản port. Luật và hiệu ứng tiếp tục do OCG core cùng CardScripts đã pin quyết định.

## Tài nguyên đã đối chiếu trong OBB

- `assets/cir_bg.png`: ảnh mạch điện xanh/tím thực, 2048×1536. Dùng làm nền menu
  native; đây là lựa chọn cùng phong cách màn campaign, không phải tái tạo toàn bộ
  hoạt ảnh menu trong video.
- `assets/card_rear.png`: mặt sau thẻ cổ điển, 153×214. Dùng cho cả `cover.png` và
  `cover2.png` của EDOPro. Tất cả bản sao giữ nguyên byte nguồn.
- `gs_background.png`, `gamescreen_bg.png`, `mainMenuBg.png` là placeholder có
  alpha bằng 0 ở mọi pixel. Không dùng các file này làm nền chỉ vì tên có vẻ phù hợp.
- `grid_bg_shine_3.png` là lớp lưới nhiều màu; `grid_bg_2.png` là nền xanh đậm 2×2.
  Có thể dùng khi đối chiếu thêm cách ghép lớp/hoạt ảnh, nhưng chưa bật làm nền đấu.
- `cardFrame_0.png` có khung Normal thật. Mapping đủ các khung 1…13 và vùng chữ/
  tranh cần kiểm tra riêng trước khi thay compositor hiện có.

Manifest của payload ghi nguồn, đích và SHA256 trong `originalUITextures` và
`reports/ui-textures.json`. File placeholder, atlas mask và ảnh chưa được kiểm
chứng không được tự gán vào skin đang hoạt động.

## Phần đã triển khai trong mã nguồn

- Bố cục chung `duel_layout.h`: thông tin/ảnh thẻ ở trái, bàn đấu nhìn từ trên ở
  giữa, LP và chân dung ở phải. Phép chiếu camera và hit-testing cùng dùng hình
  học này; các ngưỡng x=300 cũ đã được thay trên iOS. Bỏ nhận chọn ô khi kích thước
  driver chưa khớp frame đã render để tránh dùng tọa độ cũ.
- UIKit đọc safe-area và kích thước theo point trên main queue. Game giữ snapshot
  cho từng frame; bố cục chỉ cập nhật cùng projection, không đọc UIKit từ luồng duel.
  Kích thước ưu tiên 44 point được quy đổi sang pixel khi có metrics; trước đó dùng
  mặc định có scale. Kích thước quá nhỏ có thể phải nén điều khiển.
- LP lấy từ `dInfo`, giữ animation thay đổi LP một lần mỗi frame. Bố trí chữ dựa
  trên chiều cao font; giữ nguyên chữ số LP, thu nhỏ vùng chân dung trước khi dùng
  chế độ chỉ hiển thị LP ở viewport/font quá nhỏ/lớn.
- Bảng chọn/xem thẻ iOS có 5 cột × 3 hàng, cuộn theo hàng, số lượng và OK/Cancel.
  Click/hover/cuộn dùng cùng phép ánh xạ chỉ số; logic min/max, sum, sort và chain
  của engine được giữ. Không chuyển phase/shuffle trong lúc bảng đang mở.
- Exit/Restart/Chain được gom vào menu điều khiển bên phải, tránh đè lên ảnh thẻ.
  Menu không thay `dField.panel` của engine; đóng menu trả focus về panel đang chờ.
  Nhấn ngoài menu được tiêu thụ, không truyền xuống bàn đấu. Đây không phải pause.
- Phase nằm ngang dưới tay bài. Đây là điều chỉnh so với video: MR5 có Extra
  Monster Zones ở giữa nên không đặt thanh nút đè lên các ô đó.

## Chân dung đúng theo bản APK/OBB đã cung cấp

`NativeClient/overlays/ui-layout/portrait-source-map.json` ghi bằng chứng từ các
bảng pointer của `GetNPCDeckKeyWord`, `GetOpponentName`, `GetOpponentIcon` trong
APK. Với chỉ số 80…99, callsite cộng 26 trước khi lấy icon; không suy luận mapping
ARC-V từ tên file. Tên hiển thị được kiểm tra lại với `LocalizationNpcNames_E.plist`
vì bản mod đã thay tên/nhân vật so với tên gốc.

Payload v6 chứa 100 portrait NPC và một avatar người chơi, ghép cho 200 deck NPC
đã chuyển đổi. 451 deck hợp lệ khác không có liên kết NPC xác thực dùng avatar
trung tính; chúng vẫn dùng được như trước. Ảnh giữ nguyên byte từ OBB, kiểm tra
SHA256 và alpha. Avatar người chơi chỉ là lựa chọn trang trí, không đổi nickname.

## Phạm vi kiểm chứng

Đã kiểm tra dữ liệu, source mapping, đường dẫn và copy toàn bộ payload; đã tạo
project Xcode để kiểm tra cấu trúc. Các assert C++ cho layout, HUD, phép chiếu và
grid dùng trực tiếp production headers đã viết trong `overlays/ui-layout/tests`,
nhưng chưa biên dịch/chạy. Chưa có screenshot từ bản iOS hoặc kiểm chứng cảm ứng,
font, safe-area và hiệu năng trên thiết bị. Không tuyên bố giống video từng pixel.

Chưa chạy compiler, GitHub Actions hoặc tạo IPA cho bước thay đổi giao diện này.
