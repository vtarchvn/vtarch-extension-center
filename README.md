# VTARCH Extension Center (VEC)

Plugin Manager cho SketchUp 2021+, hỗ trợ cài file `.rb`, cài gói `.rbz`, sao lưu, khôi phục, profiles và chuyển an toàn các plugin do VEC theo dõi.

## Cài đặt

Nén **nội dung** gồm `vtarch_vec.rb` và thư mục `vtarch_vec/` thành tệp ZIP, sau đó đổi đuôi tệp thành `.rbz`. Trong SketchUp mở **Extension Manager → Install Extension** và chọn tệp `.rbz`.

Mở VEC qua **Extensions → VTARCH Extension Center**.

## Quy tắc an toàn

- VEC chỉ chuyển plugin được cài qua VEC vào backup; VEC không xóa file plugin.
- RBZ được đọc trước khi cài, từ chối ZIP mã hóa/đường dẫn nguy hiểm và lưu danh sách file để có thể chuyển cả plugin vào backup về sau.
- Tab **Chẩn đoán** kiểm tra phiên bản SketchUp, thư mục Plugins/backup, quyền ghi và file plugin bị thiếu.
- Mỗi lần gỡ hoặc ghi đè file `.rb`, VEC tạo bản backup có `manifest.json`.
- Thay đổi plugin thường chỉ có hiệu lực sau khi đóng và mở lại SketchUp.
