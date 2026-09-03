# VTARCH Extension Center (VEC)

Plugin Manager cho SketchUp 2021+, hỗ trợ cài file `.rb`, cài gói `.rbz`, sao lưu, khôi phục và gỡ an toàn các plugin do VEC theo dõi.

## Cài đặt

Nén **nội dung** gồm `vtarch_vec.rb` và thư mục `vtarch_vec/` thành tệp ZIP, sau đó đổi đuôi tệp thành `.rbz`. Trong SketchUp mở **Extension Manager → Install Extension** và chọn tệp `.rbz`.

Mở VEC qua **Extensions → VTARCH Extension Center**.

## Quy tắc an toàn

- VEC chỉ chuyển các script `.rb` được cài qua VEC vào backup; VEC không xóa file plugin. Với `.rbz`, VEC dùng trình cài đặt chuẩn của SketchUp; việc xác định chính xác mọi file bên trong để chuyển an toàn sẽ được bổ sung ở phiên bản sau.
- Mỗi lần gỡ hoặc ghi đè file `.rb`, VEC tạo bản backup có `manifest.json`.
- Thay đổi plugin thường chỉ có hiệu lực sau khi đóng và mở lại SketchUp.
