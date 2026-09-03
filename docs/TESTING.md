# Kiểm thử VEC

## Tự động trước khi phát hành

1. Kiểm tra cú pháp JavaScript: `node --check vtarch_vec/ui/app.js`.
2. Nén `vtarch_vec.rb` và thư mục `vtarch_vec/` ở gốc ZIP, rồi đổi đuôi thành `.rbz`.
3. Kiểm tra ZIP có loader `vtarch_vec.rb`, `vtarch_vec/main.rb`, `vtarch_vec/zip_archive.rb` và UI.

## Kiểm thử trong SketchUp 2021+

1. Cài `VTARCH_VEC.rbz`, khởi động lại, mở **Extensions > VTARCH Extension Center**.
2. Mở tab **Chẩn đoán**, xác nhận Plugins và Backup có quyền ghi.
3. Cài một file `.rb` thử nghiệm; kiểm tra file được theo dõi.
4. Sao lưu, chọn **Chuyển vào backup**, khởi động lại SketchUp và xác nhận script không còn ở Plugins.
5. Khôi phục, khởi động lại và xác nhận script quay về đúng đường dẫn.
6. Cài một `.rbz` thử nghiệm có thư mục con; xác nhận mọi file xuất hiện, sau đó chuyển vào backup và khôi phục.
7. Tạo Profile, thay đổi trạng thái một extension thử nghiệm, áp dụng profile và khởi động lại.

Không thử chuyển VEC vào backup hoặc tắt VEC trong chính phiên đang dùng.
