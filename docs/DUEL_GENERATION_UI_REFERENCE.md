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
| [Khoảng 9:00](https://www.youtube.com/watch?v=a1tYUTDbrcY&t=540s) | Bàn đấu nhìn từ trên; tay bài phía dưới, phase ở giữa, LP/chân dung đối thủ và người chơi ở phải. Menu hành động nổi có Xem/Kích hoạt. | Tăng khả năng chạm menu hành động, giữ menu trong vùng hiển thị; chưa thay camera/hit-testing của bàn đấu. |

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

## Ranh giới của bước sửa hiện tại

Menu hành động iOS dùng nút cao/rộng hơn, được giới hạn trong vùng clip của phần
tử cha. Kích thước là đơn vị scale/pixel của EDOPro; chưa chứng minh được kích
thước chạm thực tế theo point hoặc khoảng tránh tai thỏ/home indicator trên iPhone.

Bản port vẫn dùng bố cục bàn đấu, LP và hộp chọn thẻ của client EDOPro. Việc chuyển
LP/chân dung sang phải, giữ sáu phase luôn hiện ngang, hoặc thay bảng chọn 5 lá
thành lưới nhiều hàng cần sửa UI cùng phép chiếu/tọa độ chạm và kiểm tra runtime.
Không ghi nhận các phần đó là đã hoàn thành chỉ vì đã có ảnh nguồn.

Chưa chạy compiler, GitHub Actions hoặc tạo IPA cho bước thay đổi giao diện này.
