# Phạm vi duel offline

Đây là engine native mới đang được phát triển, không phải bản chuyển đổi của
`libcocos2dcpp.so`. Chỉ các luật và lá bài được ghi rõ dưới đây mới thuộc phạm vi
thử nghiệm. Chưa chạy Xcode, simulator, IPA hoặc GitHub Actions sau thay đổi này.

## Chế độ luyện tập

- Chơi với AI heuristic cục bộ hoặc hai người luân phiên trên cùng thiết bị.
- Hai bộ bài riêng, mỗi bộ đúng 40 lá Main, tối đa 3 bản sao mỗi lá.
- Extra và Side trống. Không áp dụng banlist thi đấu trong bộ luyện tập.
- Mỗi bộ có 26 Normal Monster có ATK/DEF xác định; có lá cần 1 và 2 vật tế.
  14 lá còn lại là tám loại Phép/Bẫy đã cho phép ở bảng bên dưới.
- Mọi ID và thông số trong bộ luyện tập được lấy từ OBB đã cung cấp.
- Bộ bài nguồn từ 799 file YDC dùng cho tra cứu. Không mặc nhiên coi mọi bộ bài
  nguồn là chơi được bằng engine này.

`GeneratedData/offline-practice-decks.json` là đầu vào của chế độ luyện tập.
Thứ tự trong JSON cố định; engine có thể xáo bài khi bắt đầu ván. Không suy luận
effect bằng cách tìm từ khóa trong mô tả thẻ.

| Konami ID | Lá bài | Password | Phần effect được triển khai trong core |
|---|---|---|---|
| 4844 | Pot of Greed | 55144522 | Rút 2 lá khi chain giải quyết |
| 4349 | Sparks | 76103675 | Gây 200 sát thương khi chain giải quyết |
| 4348 | Dian Keto the Cure Master | 84257639 | Hồi 1000 LP khi chain giải quyết |
| 4861 | Solemn Judgment | 41420027 | Phản hồi activation được hỗ trợ, trả nửa LP; không bao gồm phủ nhận triệu hồi |
| 4842 | Monster Reborn | 83764718 | Chọn một Normal Monster trong Mộ của một trong hai người và Special Summon về sân người kích hoạt |
| 11740 | Unexpected Dai | 00911883 | Khi không điều khiển quái: chọn Normal Monster cấp 4 trở xuống trong Deck khi giải quyết để Special Summon |
| 4343 | Raigeki | 12580477 | Phá hủy toàn bộ quái trên sân đối phương |
| 4342 | Dark Hole | 53129443 | Phá hủy toàn bộ quái trên cả hai sân |

Trong OBB, tên và password của cả tám lá khớp nhau. Mô tả Solemn Judgment có
phạm vi rộng hơn phần đang hỗ trợ (bao gồm phủ nhận triệu hồi); không coi việc
đọc được mô tả là đã thực thi đầy đủ effect.

Monster Reborn có mục tiêu chọn lúc kích hoạt; mục tiêu phải còn ở Mộ khi giải
quyết. Unexpected Dai không có từ "target" trong mô tả: chỉ chọn lá từ Deck ở
bước giải quyết, không đưa lựa chọn này lên chain như một mục tiêu. Việc triệu
hồi bằng effect không tiêu tốn lượt Normal Summon. Bộ luyện tập chỉ chứa Normal
Monster nên không xử lý điều kiện hồi sinh của các loại Extra Deck Monster.

Mystical Space Typhoon (`4909`, password `05318639`, icon Quick-Play `5`) đã xác
định được trong OBB nhưng **chưa được cho phép trong engine hoặc bộ luyện tập**.
Effect này phá hủy Spell/Trap chứ không negate. Cần xử lý cả thời điểm Quick-Play
và nguồn chain bị phá hủy trước khi hỗ trợ đúng.

Mô tả bốn lá mới đã được đối chiếu thêm với database chính thức Konami:
[Monster Reborn](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4842&request_locale=en),
[Unexpected Dai](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=11740&request_locale=en),
[Raigeki](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4343&request_locale=en),
[Dark Hole](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4342&request_locale=en).

## Những phần chưa hỗ trợ

- Effect Monster, các kiểu Special Summon ngoài Monster Reborn/Unexpected Dai,
  Fusion/Ritual/Synchro/Xyz/Pendulum/Link.
- Battle response windows, replay, damage-step trigger và các effect không nằm
  trong whitelist trên.
- Quick-Play (bao gồm Mystical Space Typhoon), chơi mạng, chiến dịch, shop,
  saved game và toàn bộ luật gốc của Konami.

Không cho phép lá chưa hỗ trợ âm thầm hoạt động như Normal Monster, và không
dùng nút gây sát thương/rút bài miễn phí thay cho việc kích hoạt lá trên tay.
Màn hình và engine phải thông báo khi dữ liệu hoặc thao tác không được hỗ trợ.

## Luồng lượt và chain hiện tại

`DuelState.swift` tách luật khỏi SwiftUI. Mỗi bản sao lá bài có ID riêng; reset
khôi phục bộ bài đầy đủ. Người đi trước không rút hoặc vào Battle Phase trong
lượt đầu; các lượt sau chỉ người đang có lượt rút một lá. End Phase yêu cầu
chọn bỏ bài về tối đa 6 lá. Quái Normal được triệu hồi/úp một lần mỗi lượt,
cần 1 vật tế ở cấp 5–6 hoặc 2 vật tế ở cấp 7 trở lên, tối đa 5 ô quái.

Tấn công kiểm tra tư thế và số lần đánh của từng quái. Có quái đối phương thì
phải chọn mục tiêu; so ATK/ATK hoặc ATK/DEF để xử lý sát thương và Mộ bài.
Hết LP hoặc không có bài để rút kết thúc trận; các thao tác tiếp theo bị từ chối.

Kích hoạt Phép đưa lá bài vào chain thay vì áp dụng ngay. Quyền phản hồi đổi
giữa hai người. Hai lần bỏ qua liên tiếp giải quyết chain từ cuối lên; không
được đổi phase, triệu hồi hoặc đánh khi chain chưa kết thúc. Solemn Judgment
phải được úp từ lượt trước và trả nửa LP ngay khi kích hoạt, kể cả nếu bị negate.

Trong chế độ hai người, màn hình yêu cầu chuyển máy trước khi hiện tay bài của
người kế tiếp. Chế độ AI tự chọn thao tác trong phạm vi core cho phép.

## AI hiện tại

AI là bộ heuristic xác định, không phải CPU engine gốc. Nó chỉ sử dụng tay bài
của chính nó, sân công khai và Mộ để lựa chọn thao tác; không đọc tay bài, thứ tự
Deck hoặc định nghĩa lá úp của đối phương. Với Unexpected Dai, nó chỉ xem tập
các lá đủ điều kiện khi hiệu ứng cho phép tìm Deck, không dự đoán lần rút sau.

AI ưu tiên thao tác hợp lệ, các effect đã hỗ trợ, triệu hồi, chọn mục tiêu và
chiến đấu theo thông số hiện có. Nó cũng có thể bỏ qua chain, chọn lá cho effect
triệu hồi và bỏ bài cuối lượt. Đây là đối thủ luyện tập cơ bản, chưa phải chiến
thuật tối ưu hay bằng chứng mọi ván đều xử lý đúng; cần chạy các self-check và
thử trên thiết bị sau khi được phép.

Luật cơ bản được đối chiếu với [rulebook Konami](https://img.yugioh-card.com/en/downloads/rulebook/SD_RuleBook_EN_10.pdf).
Việc đối chiếu tài liệu không thay thế kiểm thử engine.

## Dữ liệu và kiểm tra offline

Chạy kiểm tra dữ liệu từ bất kỳ thư mục hiện hành nào bằng đường dẫn đến script:

```powershell
python YuGiOhNativeIOS/Tools/verify_duel_data.py
```

Đường dẫn mặc định tới OBB và JSON được tính từ `__file__`, không dựa vào thư mục
hiện hành. Có thể truyền `--obb` và `--report` để kiểm tra một bản sao riêng.
Script chỉ đọc OBB/JSON và ghi báo cáo `GeneratedData/duel-data-validation.json`.
Nó không gọi Swift, Xcode hoặc GitHub.

Các kiểm tra gồm:

- UTF-16 strict, terminator trên biên 2 byte; đối chiếu tên/mô tả từng thẻ với
  cặp offset tên/mô tả trong `CARD_Indx_E.bin`.
- Đối chiếu 7.581 record Prop/Genre (gồm record rỗng), password, ID và bảng
  `CARD_IntID`; kiểm tra bản generated và bản resource giống nhau.
- Dựng lại toàn bộ 799 YDC từ JSON, so sánh từng byte với tệp trong OBB.
- Đối chiếu tên cho từng Konami ID; không nhầm Konami ID với internal index.
- Kiểm tra hai bộ luyện tập đúng schema, đủ 40 lá, tối đa 3 bản sao, không có
  Extra/Side, ít nhất 24 Normal Monster và chỉ có tám effect đã cho phép;
  đối chiếu cả password lẫn tên của mỗi effect với OBB.

Hai ID `10855` (Number 94: Crystalzero) và `11766` (Number S39: Utopia the
Lightning) chỉ có tên bổ sung trong bảng tra cứu. OBB không có Prop cho chúng,
và `CARD_IntID` trả 0. Chúng không phải card definition chơi được và không có
trong bộ luyện tập. Vì vậy 5.215/5.215 tên trong deck có thể hiển thị, nhưng chỉ
5.213 ID có dữ liệu thẻ gốc; coverage tên không chứng minh coverage gameplay.

Các lần trước tách chuỗi bằng null và dùng vị trí chuỗi làm internal ID gây lệch
tên/mô tả. Báo cáo mới kiểm tra trực tiếp mọi record với OBB, thay vì tin vào
report cũ. Nó cũng giữ `portComplete: false` và
`engineBehaviorTestsExecuted: false`: kiểm tra dữ liệu Python không thay thế
việc thực thi self-check Swift và thử game trên thiết bị sau khi được phép.

`Tests/duel_state_checks.swift` gọi trực tiếp core để kiểm tra lượt, reset,
hiến tế, chiến đấu, các lệnh không hợp lệ, chi phí/negate/chain ba liên kết,
bỏ bài, deck-out và việc không mất/nhân đôi lá bài. Các self-check này **chưa
được thực thi**: máy hiện không có Swift và chưa được phép build app. Không
đưa file `@main` của self-check vào app target.

Các kiểm tra cho Special Summon, phá hủy quái và AI được bổ sung trong source
self-check; chúng cũng **chưa được thực thi**. Báo cáo Python chỉ xác nhận dữ
liệu tương ứng, không báo pass thay cho những kiểm tra Swift chưa chạy.
