# Phạm vi duel offline

Đây là engine native mới đang được phát triển, không phải bản chuyển đổi của
`libcocos2dcpp.so`. Chỉ các luật và lá bài được ghi rõ dưới đây mới thuộc phạm vi
thử nghiệm. Chưa chạy Xcode, simulator, IPA hoặc GitHub Actions sau thay đổi này.

## Chế độ luyện tập

- Chơi với AI heuristic cục bộ hoặc hai người luân phiên trên cùng thiết bị.
- Hai bộ bài riêng, mỗi bộ đúng 40 lá Main và 2 lá Extra; tối đa 3 bản sao mỗi
  lá khi cộng Main/Extra. Side trống, không áp dụng banlist thi đấu.
- Mỗi Main Deck có 18 Normal Monster, 3 Tune Warrior, 2 Kuriboh, 2 Cyber Dragon
  và 15 Phép/Bẫy. Có quái cần 1 và 2 vật tế, cùng đủ hai nguyên liệu Fusion.
- Extra Deck chỉ có Flame Swordsman và Gaia Knight, the Force of Earth, mỗi loại
  một lá. Chưa hỗ trợ toàn bộ các họ Fusion/Synchro hoặc mọi Extra Deck Monster.
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
| 4861 | Solemn Judgment | 41420027 | Trả nửa LP để phủ nhận kích hoạt Phép/Bẫy, Normal Summon hoặc Flip Summon trong cửa sổ tương ứng |
| 4842 | Monster Reborn | 83764718 | Chọn một Normal Monster trong Mộ của một trong hai người và Special Summon về sân người kích hoạt |
| 11740 | Unexpected Dai | 00911883 | Khi không điều khiển quái: chọn Normal Monster cấp 4 trở xuống trong Deck khi giải quyết để Special Summon |
| 4343 | Raigeki | 12580477 | Phá hủy toàn bộ quái trên sân đối phương |
| 4342 | Dark Hole | 53129443 | Phá hủy toàn bộ quái trên cả hai sân |
| 4909 | Mystical Space Typhoon | 05318639 | Quick-Play: chọn một Phép/Bẫy trên sân để phá hủy; không phủ nhận effect |
| 4887 | Mirror Force | 44095762 | Khi đối phương tuyên bố tấn công: phá hủy tất cả quái thế công trên sân đối phương |
| 4064 | Kuriboh | 40640057 | Bỏ từ tay trong Damage Calculation khi đối phương tấn công để không nhận battle damage của trận chiến đó |
| 6390 | Cyber Dragon | 70095154 | Special Summon từ tay khi chỉ đối phương có quái trên sân; không dùng chain |
| 5914 | Compulsory Evacuation Device | 94192409 | Chọn một quái trên sân để trả về tay; Extra Deck Monster trở về Extra Deck |
| 4837 | Polymerization | 24094653 | Fusion Summon Flame Swordsman bằng hai nguyên liệu cụ thể từ tay/sân; chọn khi chain giải quyết |

Registry hiện có 14 identity được script: 12 Phép/Bẫy và 2 Effect Monster.
Trong OBB, tên, password và kind của các lá này khớp nhau. Việc đọc
được mô tả không đồng nghĩa mọi tình huống luật đã được kiểm thử. Không mở cửa
sổ phủ nhận triệu hồi giữa lúc Monster Reborn hoặc Unexpected Dai đang giải
quyết: muốn chặn các lá này bằng Solemn Judgment phải phủ nhận kích hoạt Phép.

Monster Reborn có mục tiêu chọn lúc kích hoạt; mục tiêu phải còn ở Mộ khi giải
quyết. Unexpected Dai không có từ "target" trong mô tả: chỉ chọn lá từ Deck ở
bước giải quyết, không đưa lựa chọn này lên chain như một mục tiêu. Việc triệu
hồi bằng effect không tiêu tốn lượt Normal Summon. Phạm vi hồi sinh chỉ gồm các
quái core hỗ trợ; quái Extra Deck cần được triệu hồi đúng cách trước đó mới
được hồi sinh, không hồi sinh quái vừa bị phủ nhận triệu hồi.

| Konami ID | Vật liệu/quái Extra | Password | Kind, cấp và vai trò |
|---|---|---|---|
| 4148 | Flame Manipulator | 34460851 | Normal, cấp 3; nguyên liệu thứ nhất của Flame Swordsman |
| 4299 | Masaki the Legendary Swordsman | 44287299 | Normal, cấp 4; nguyên liệu thứ hai |
| 7684 | Tune Warrior | 74093656 | Normal Tuner (kind 15), cấp 3 |
| 4021 | Flame Swordsman | 45231177 | Fusion không effect (kind 2), cấp 5, ATK 1800/DEF 1600 |
| 7697 | Gaia Knight, the Force of Earth | 97204936 | Synchro không effect (kind 17), cấp 6, ATK 2600/DEF 800 |

Polymerization chỉ hỗ trợ công thức Flame Manipulator + Masaki trong lần này,
không dùng bộ giải công thức Fusion tổng quát. Gaia Knight cần đúng 1 Tuner và
ít nhất 1 non-Tuner ngửa trên sân, tổng cấp chính xác là 6. Tune Warrior cấp 3
ghép được với Flame Manipulator hoặc một non-Tuner cấp 3 trong bộ luyện tập.
Hai quái Extra là whitelist riêng, không được đếm thành hai card effect.

Mystical Space Typhoon có icon Quick-Play `5`; Mirror Force là Normal Trap với
icon `0`. MST được dùng từ tay trong lượt của mình hoặc từ lá đã úp ở lượt
trước. MST/Mirror Force thuộc Spell Speed 2, không nối phía sau Counter Trap
Spell Speed 3. Phá hủy một lá Phép/Bẫy đang nằm trên chain không tự phủ nhận
effect của nó. Các trường hợp này được bổ sung thành self-check nhưng chưa chạy.

Mô tả bốn lá mới đã được đối chiếu thêm với database chính thức Konami:
[Monster Reborn](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4842&request_locale=en),
[Unexpected Dai](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=11740&request_locale=en),
[Raigeki](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4343&request_locale=en),
[Dark Hole](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4342&request_locale=en).

Hai lá mới tiếp tục được đối chiếu với database chính thức:
[Mystical Space Typhoon](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4909&request_locale=en),
[Mirror Force](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4887&request_locale=en).

Các lá mới cũng đã đối chiếu với database Konami:
[Kuriboh](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4064&request_locale=en),
[Cyber Dragon](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=6390&request_locale=en),
[Compulsory Evacuation Device](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=5914&request_locale=en),
[Polymerization](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4837&request_locale=en),
[Flame Swordsman](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=4021&request_locale=en),
[Gaia Knight](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=2&cid=7697&request_locale=en).
Mô tả OBB có câu chữ của bản game cũ, ví dụ Kuriboh ghi điều kiện lượt đối
phương; catalog giữ nguyên text nguồn thay vì ghi đè bằng text website mới.

## Những phần chưa hỗ trợ

- Effect Monster ngoài Kuriboh/Cyber Dragon, những công thức Fusion/Synchro khác,
  Ritual/Xyz/Pendulum/Link và các điều kiện Special Summon ngoài phạm vi đã nêu.
- Hệ thống trigger/effect tổng quát ở từng bước Damage Step; chỉ xử lý chiến đấu
  của các quái đang hỗ trợ và timing Kuriboh. Chưa có Flip Effect Monster.
- Chơi mạng, chiến dịch, shop, saved game và toàn bộ luật gốc của Konami.

Không cho phép lá chưa hỗ trợ âm thầm hoạt động như Normal Monster, và không
dùng nút gây sát thương/rút bài miễn phí thay cho việc kích hoạt lá trên tay.
Màn hình và engine phải thông báo khi dữ liệu hoặc thao tác không được hỗ trợ.

## Luồng lượt và chain hiện tại

`DuelState.swift` tách luật khỏi SwiftUI. Mỗi bản sao lá bài có ID riêng; reset
khôi phục bộ bài đầy đủ. Người đi trước không rút hoặc vào Battle Phase trong
lượt đầu; các lượt sau chỉ người đang có lượt rút một lá. End Phase yêu cầu
chọn bỏ bài về tối đa 6 lá. Quái Normal được triệu hồi/úp một lần mỗi lượt,
cần 1 vật tế ở cấp 5–6 hoặc 2 vật tế ở cấp 7 trở lên, tối đa 5 ô quái. Điều kiện
này cũng áp dụng khi Normal Summon các Effect Monster đang được hỗ trợ.

Tấn công kiểm tra tư thế và số lần đánh của từng quái. Có quái đối phương thì
phải chọn mục tiêu. Tuyên bố tấn công mở cửa sổ phản hồi trước khi so ATK/ATK
hoặc ATK/DEF; Mirror Force có thể phá hủy quái tấn công trước khi gây sát thương.
Hết LP hoặc không có bài để rút kết thúc trận; các thao tác tiếp theo bị từ chối.

Damage Step được chia thành 5 bước để giữ đúng timing của Kuriboh; việc chia
bước không đồng nghĩa đã có tất cả trigger của game gốc. Khi đội hình đối phương
thay đổi trước Damage Step (ví dụ do Compulsory Evacuation Device), người tấn
công được chọn lại mục tiêu hoặc dừng ở bước replay; không dùng lại Mirror Force
như thể đây là một tuyên bố tấn công mới.

Kích hoạt Phép đưa lá bài vào chain thay vì áp dụng ngay. Quyền phản hồi đổi
giữa hai người. Hai lần bỏ qua liên tiếp giải quyết chain từ cuối lên; không
được đổi phase, triệu hồi hoặc đánh khi chain chưa kết thúc. Solemn Judgment
phải được úp từ lượt trước và trả nửa LP ngay khi kích hoạt, kể cả nếu bị negate.
Normal Summon và Flip Summon cũng có bước chờ quyết định phủ nhận; các quái
hiến tế đã trả không được hoàn lại nếu triệu hồi bị phủ nhận. Úp quái không
được coi là Normal Summon ngửa để kích hoạt Solemn Judgment.
Cyber Dragon và Synchro Summon Gaia Knight cũng có cửa sổ phủ nhận triệu hồi.
Fusion qua Polymerization nằm trong resolution của Phép nên không mở cửa sổ
Judgment riêng ngay giữa resolution.

Trong chế độ hai người, màn hình yêu cầu chuyển máy trước khi hiện tay bài của
người kế tiếp. Chế độ AI tự chọn thao tác trong phạm vi core cho phép.

## AI hiện tại

AI là bộ heuristic xác định, không phải CPU engine gốc. Nó chỉ sử dụng tay bài
của chính nó, sân công khai và Mộ để lựa chọn thao tác; không đọc tay bài, thứ tự
Deck hoặc định nghĩa lá úp của đối phương. Với Unexpected Dai, nó chỉ xem tập
các lá đủ điều kiện khi hiệu ứng cho phép tìm Deck, không dự đoán lần rút sau.

AI ưu tiên thao tác hợp lệ, các effect đã hỗ trợ, triệu hồi, chọn mục tiêu và
chiến đấu theo thông số hiện có. Nó cũng có thể phản hồi hoặc bỏ qua cửa sổ,
chọn lá cho effect triệu hồi và bỏ bài cuối lượt. Đây là đối thủ luyện tập cơ bản, chưa phải chiến
thuật tối ưu hay bằng chứng mọi ván đều xử lý đúng; cần chạy các self-check và
thử trên thiết bị sau khi được phép.

Luật cơ bản được đối chiếu với [rulebook Konami](https://img.yugioh-card.com/en/downloads/rulebook/SD_RuleBook_EN_10.pdf).
Quyền phản hồi được đối chiếu với [Fast Effect Timing của Konami](https://www.yugioh-card.com/en/play/fast-effect-timing/).
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
  Side, đúng hai Extra Monster cho phép, đủ Fusion materials/Normal Tuner và
  Kuriboh/Cyber Dragon; đối chiếu password, tên, kind, cấp và icon với OBB.
- Đối chiếu tĩnh các cặp `(kind, password)` trong registry của `DuelState.swift`
  với đúng 14 effect identities và whitelist Extra riêng gồm 2 identities;
  phát hiện khi code lệch dữ liệu. Đây không phải kiểm thử effect hoặc biên dịch Swift.

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

Phần mới thêm các kịch bản phủ nhận triệu hồi, Mirror Force khi tuyên bố tấn
công và chain Quick-Play/Counter Trap. Chưa chạy những self-check này, chưa
kiểm tra UI trên thiết bị và chưa build IPA sau thay đổi.

Các trường hợp Kuriboh ở Damage Calculation, Cyber Dragon, replay do CED,
Fusion bằng Polymerization và Synchro Gaia Knight tiếp tục được viết thành
self-check. Chúng vẫn chỉ là test source chưa thực thi, không phải kết quả pass.
