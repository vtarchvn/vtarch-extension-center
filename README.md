# VTARCH Extension Center (VEC)

Plugin Manager cho SketchUp 2021+, hỗ trợ cài file `.rb`, cài gói `.rbz`, sao lưu, khôi phục, profiles và chuyển an toàn các plugin do VEC theo dõi.

## Tính năng

- Cài và xem trước plugin `.rb` / `.rbz`; nhận diện thư mục phụ trợ `.rb` cùng tên.
- Backup và khôi phục có manifest; chuyển plugin vào backup thay vì xóa.
- Bật/tắt extension chuẩn, Profiles và thông báo khởi động lại.
- Lọc/sắp xếp danh sách plugin, nhật ký tìm kiếm được và báo cáo chẩn đoán JSON.
- Bảo vệ cài đặt RBZ: chặn ZIP mã hóa, path traversal và gói quá lớn.

## Cài đặt

Nén **nội dung** gồm `vtarch_vec.rb` và thư mục `vtarch_vec/` thành tệp ZIP, sau đó đổi đuôi tệp thành `.rbz`. Trong SketchUp mở **Extension Manager → Install Extension** và chọn tệp `.rbz`.

Mở VEC qua **Extensions → VTARCH Extension Center**.

## Phát hành

Phiên bản phát hành hiện tại: `1.0.0` (đang chuẩn bị). Xem [CHANGELOG.md](CHANGELOG.md) và [docs/TESTING.md](docs/TESTING.md) trước khi phát hành.

## Quy tắc an toàn

- VEC chỉ chuyển plugin được cài qua VEC vào backup; VEC không xóa file plugin.
- RBZ được đọc trước khi cài, từ chối ZIP mã hóa/đường dẫn nguy hiểm và lưu danh sách file để có thể chuyển cả plugin vào backup về sau.
- Tab **Chẩn đoán** kiểm tra phiên bản SketchUp, thư mục Plugins/backup, quyền ghi và file plugin bị thiếu.
- Mỗi lần gỡ hoặc ghi đè file `.rb`, VEC tạo bản backup có `manifest.json`.
- Thay đổi plugin thường chỉ có hiệu lực sau khi đóng và mở lại SketchUp.
