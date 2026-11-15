# EDOPro iOS + dữ liệu OBB

## Quyết định và phạm vi

Dùng lại client native EDOPro để nhận toàn bộ luồng bàn đấu và các prompt của engine. Tránh tiếp tục mở rộng engine Swift bằng danh sách thẻ riêng lẻ. SwiftUI prototype có thể giữ làm công cụ đối chiếu, nhưng việc parse dữ liệu thành công không chứng minh duel đã chơi đúng luật.

Không chạy build ở giai đoạn hiện tại. Đã sinh project Xcode bằng Premake trên
Windows để kiểm tra cấu trúc, không gọi compiler. Cấu hình hiện hành và dependency
đã khóa được ghi tại [NativeClient/iOS/README.md](../NativeClient/iOS/README.md);
project phải được sinh lại trên macOS với đường dẫn của runner trước khi build.

## Pin và nguồn bằng chứng

| Thành phần | Revision | Bằng chứng dùng trong quyết định |
|---|---|---|
| EDOPro client | `d0f111d6f3e0d4ee529b88a869ae0a971954bae3` | [README](https://github.com/edo9300/edopro/blob/d0f111d6f3e0d4ee529b88a869ae0a971954bae3/README.md), `gframe/iOS`, `gframe/premake5.lua` |
| Core của client | `46779fbe40e6a9bd8967f5dc6a03f4eaa6550d57` | Gitlink `ocgcore` của revision client; C API 11.0 trong `ocgapi_types.h` |
| Lua của core | `6e22fedb74cf0c9b6656e9fce8b7331db847c605` | Gitlink `lua/src`; `lua.h` ghi phiên bản 5.4.8 |
| Upstream dependency recipes | `5905a0e9fb4c4263ab5e9199d59ffc6d7be3ca00` | [`edo9300/edopro-vcpkg-cache`](https://github.com/edo9300/edopro-vcpkg-cache/tree/5905a0e9fb4c4263ab5e9199d59ffc6d7be3ca00) |
| Irrlicht branch khảo sát | `7071bec37b1aa1a663f662dc1372f9e476aae009` | [`edo9300/irrlicht1-8-4`, `1.9-custom`](https://github.com/edo9300/irrlicht1-8-4/tree/7071bec37b1aa1a663f662dc1372f9e476aae009) |

Irrlicht/dependency recipes là pin tham khảo đã đọc, chưa phải một dependency closure đã build thành công. Vcpkg baseline và checksum của từng archive dependency phải được khóa trước khi tạo bản reproducible cuối cùng. Không dùng URL `releases/latest` làm bằng chứng tái lập được.

`ProjectIgnis/ygopro-core` không phải repository core hiện hành truy cập được trong lần kiểm tra này. README của EDOPro dẫn tới `edo9300/ygopro-core`. Core HEAD khảo sát riêng là `c2e0b697e031d3560c077c9cd2cc76474969dedf`; không tự thay pin core của client bằng revision đó.

## iOS trong upstream thực sự có gì

- [`gframe/iOS/porting_ios.mm`](https://github.com/edo9300/edopro/blob/d0f111d6f3e0d4ee529b88a869ae0a971954bae3/gframe/iOS/porting_ios.mm): đường dẫn Documents, input và UIKit bridge.
- [`gframe/premake5.lua`](https://github.com/edo9300/edopro/blob/d0f111d6f3e0d4ee529b88a869ae0a971954bae3/gframe/premake5.lua): C++17, `ygopro` static core, `ygoprodll` dynamic core, iOS frameworks và Info.plist.
- [`premake5.lua`](https://github.com/edo9300/edopro/blob/d0f111d6f3e0d4ee529b88a869ae0a971954bae3/premake5.lua): `--os=ios`, arm64 và simulator architectures, `xcode4`, vcpkg include/lib paths.
- [Workflow iOS upstream](https://github.com/edo9300/edopro/blob/d0f111d6f3e0d4ee529b88a869ae0a971954bae3/.github/workflows/edopro.yml): Linux cctools + Apple SDK 16.1, các target arm64/armv7/simulator. Đây là nguồn tham khảo, không phải workflow đã chạy cho dự án này.
- `travis/predeploy.sh`: gói iOS, nhưng có bước ad-hoc/fake sign. Bản unsigned của dự án này phải bỏ các lệnh ký đó và không mang `_CodeSignature` cũ từ `ios-assets` sang.

## Dependency cần chuẩn bị

1. Xcode/Apple iPhoneOS SDK, Clang C++17 và libc++; arm64 device trước, simulator là slice riêng.
2. Premake 5 có generator `xcode4` và hỗ trợ iOS. Giữ revision/version cụ thể của công cụ khi đã xác nhận.
3. Lua theo gitlink của core, biên dịch **như C++**, forced include `lua/luaconf-customize.h`. Core kiểm tra C++ stack unwinding lúc tạo duel; Lua C mặc định không đáp ứng. Không tắt exceptions toàn cục cho Lua/core.
4. Irrlicht fork `1.9-custom`, có `CIrrDeviceiOS` và `CEAGLManager`. Overlay CMake `irrlicht-rectclip` trong cache repo không đủ để mặc định suy ra iOS support: workflow upstream build Irrlicht riêng bằng `irrlicht-cctools-makefile`, target `staticlib_ios`.
5. Các thư viện iOS static trong `installed/arm64-ios`: libevent (kèm pthread support), OpenSSL, libgit2, libssh2 phụ thuộc, curl, SQLite, FreeType, fmt, nlohmann-json, bzip2, libjpeg-turbo, libpng, zlib. Recipe upstream còn chuẩn bị libflac/libvorbis; miniaudio có source trong client và không dùng backend SFML.
6. Client đã chứa clzma và miniaudio/stb_vorbis. Chọn `--sound=miniaudio`, `--no-joystick=true`, không Discord, không Direct3D cho iOS.
7. Apple frameworks từ source: UIKit, CoreMotion, OpenGLES, Foundation, QuartzCore, CoreAudio, AudioToolbox, AVFoundation; đồng thời giữ link requirements `iconv`, `pthread` và các thư viện mà dependency tĩnh cần.

Không dùng thư viện macOS x64/arm64 cho iPhone: cùng kiến trúc arm64 không có nghĩa cùng platform ABI. Kiểm tra build-version/platform của từng library slice trước khi link.

## Recipe ứng viên dùng Xcode trên macOS

Giữ core gitlink theo client và init submodule Lua. Chuẩn bị dependency static cho `arm64-ios` bằng SDK Xcode thực tế. Sau đó generator dự kiến chạy từ `NativeClient/edopro`:

```sh
premake5 xcode4 --os=ios --architecture=arm64 \
  --vcpkg-root="$EDOPRO_VCPKG_ROOT" --ios-game-data="$EDOPRO_GAME_DATA" --sound=miniaudio \
  --no-joystick=true --no-direct3d
```

Không truyền `--no-core=true`: tùy chọn này loại target static `ygopro`, trong khi đây là target cần dùng. Không dùng nguyên `travis/build.sh` vì upstream script đang build `ygoprodll` để phân phối đa nền tảng. Sau khi tạo project, phải kiểm tra workspace/target thực tế và sửa setting cho iOS hiện hành trước khi archive.

Setting dự kiến: SDK `iphoneos`, destination `generic/platform=iOS`, kiến trúc arm64, deployment target thống nhất với ứng dụng, `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`. Dùng executable/Bundle ID/Info.plist của target mới; Info.plist upstream có nhiều giá trị toolchain cũ nên không sao chép nguyên trạng. `_LIBCPP_NO_EXCEPTIONS`/file-specific `-fno-exceptions` của `processor_visit.cpp` phải theo core build recipe, không áp dụng sang Lua.

Recipe này chỉ mô tả việc chuẩn bị tiếp theo. Chưa có chứng cứ rằng cấu hình Xcode 16 + dependency mới đã compile/link thành công; không tạo IPA giả hoặc đánh dấu hoàn tất dựa vào source alone.

## Bootstrap runtime offline

Patch `0001-bundled-game.patch` chuẩn bị `Documents/EDOPro` từ `Bundle/game` trước
`edopro_main`. Lần đầu copy qua staging rồi đổi tên nguyên tử. Khi đã có dữ liệu,
chỉ dùng lại nếu manifest trùng và các file bắt buộc hợp lệ; nếu khác thì báo lỗi và
giữ nguyên dữ liệu người dùng. Migration giữa phiên bản chưa được triển khai. Bước
copy `game` đã được triển khai và kiểm tra bằng toàn bộ payload trong một fixture;
thực thi bootstrap trên iOS vẫn chưa được kiểm chứng.

Xcode dùng resource phase gọi `copy_bundle_resources.py`, kiểm tra toàn bộ manifest
và chép nguyên cây payload thành `game`. Bản fixture đã giữ đúng các thư mục
`script`, `config`, `fonts` và `deck`; bundle có executable thực vẫn chưa được build.

Gói tối thiểu cần đủ:

- `script/constant.lua`, `script/utility.lua`, các thư viện helper và canonical `c<code>.lua` từ CardScripts đã pin.
- CDB chứa type/attribute/race/alias/setcode/scale/link đúng với scripts. OBB `Named` không phải setcode OCG, không cast trực tiếp.
- Các file cấu hình, `strings.conf`, texture, font và UI assets cần thiết từ Distribution đã pin.
- `pics/<code>.jpg` chuyển từ OBB bằng bảng Konami ID → passcode đã kiểm tra.
- Deck `.ydk` dùng passcode; giữ bản `.ydc` gốc và báo ID không chuyển được.

Phải chuẩn bị cả token và helper script mà effect có thể tạo; chỉ copy script cho những lá thấy trong deck ban đầu sẽ thiếu phụ thuộc. Giới hạn card pool trên UI khác với xóa CDB/script mà engine cần.

Không sửa nguyên APK/OBB. Không coi dữ liệu OBB, luật hiện hành trong OCG engine và UI EDOPro là bản sao đúng từng hành vi của Duel Generation. Chọn ruleset rõ ràng (ví dụ MR3 cho bối cảnh bộ bài cũ, hoặc MR5 theo luật hiện hành), rồi dùng constants của core.

## C API/protocol nếu cần lớp adapter

Pin API 11.0 dùng `OCG_CreateDuel(OCG_Duel*, const OCG_DuelOptions*)` và `OCG_DuelNewCard(..., const OCG_NewCardInfo*)`; README core còn có ví dụ signature cũ truyền struct trực tiếp. Header là nguồn chuẩn.

`OCG_DuelOptions` cần cardReader/scriptReader, payload sống suốt duel, seed 4×UInt64 không đồng thời bằng 0, hai player options, flags. CardReader trả `OCG_CardData`; setcodes là dãy UInt16 kết thúc bằng 0, được core copy rồi gọi readerDone. ScriptReader gọi `OCG_LoadScript` và trả trạng thái. Client nạp `constant.lua`, `utility.lua` trước card scripts.

`OCG_DuelProcess` → copy `OCG_DuelGetMessage` → đọc thông điệp → nếu AWAITING thì UI trả đúng `OCG_DuelSetResponse` → process tiếp. Mỗi message ở revision này có UInt32 length rồi payload mở đầu bằng UInt8 message type. Mọi query/message buffer thuộc core; copy trước lần gọi tiếp theo. Không gửi lệnh suy đoán cho prompt chưa hỗ trợ.

Full client đã có các decoder/prompt tại `gframe/duelclient.cpp`, `gframe/client_field.cpp`, `gframe/event_handler.cpp`; dùng lại chúng tiết kiệm hơn viết một bộ luật/prompt Swift mới. Không dùng scene Swift training để quyết định luật cho ocgcore.

## Offline AI và giới hạn hiện tại

WindBot Ignite không được nhúng vào bản này. `0003-offline-ai.patch` thêm duel hai
deck qua OCG core và adapter JavaScriptCore dùng `offline_ai.js` trong bundle.
Mô-đun xử lý 21 nhóm prompt theo API 11, giữ GUI cho player 0 và tự chọn cho player
1; có kiểm thử Node về lựa chọn, chain và thông tin ẩn. Không bật `DUEL_SIMPLE_AI`.
AI heuristic có giới hạn tìm kiếm, không tương đương WindBot theo từng bộ bài;
native bridge và trận đấu hoàn chỉnh chưa được chạy. Replay offline chưa hỗ trợ.

Trước khi tuyên bố hoàn tất cần kiểm tra: bootstrap sạch không mạng, card/script coverage và hashes, chọn deck và đấu đủ các prompt, effect/chain/replay/summon, lưu deck/replay, AI iPhone nếu có, suspend/resume, cảm ứng và bố cục, file unsigned đúng platform và không chứa key/profile. Những mục runtime này chưa kiểm chứng trong giai đoạn chưa build.

## Giấy phép

[EDOPro](https://github.com/edo9300/edopro/blob/d0f111d6f3e0d4ee529b88a869ae0a971954bae3/LICENSE) và [ocgcore](https://github.com/edo9300/ygopro-core/blob/46779fbe40e6a9bd8967f5dc6a03f4eaa6550d57/LICENSE) theo AGPL-3.0-or-later; Lua theo MIT. Giữ LICENSE/COPYING/notices và nguồn sửa đổi theo điều kiện giấy phép khi phân phối. Script, dependency và tài nguyên có license riêng. Quyền dùng tài nguyên OBB không phát sinh từ license của engine.
