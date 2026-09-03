# Changelog

Tất cả thay đổi đáng chú ý của VTARCH Extension Center (VEC) được ghi tại đây.

## [1.0.0] - Unreleased

### Added

- Cài và theo dõi plugin `.rb` và `.rbz`.
- Kiểm tra ZIP an toàn, xem trước file và cảnh báo ghi đè khi cài RBZ.
- Backup, chuyển plugin vào backup và khôi phục không xóa trực tiếp.
- Bật/tắt extension chuẩn, Profiles, nhập/xuất Profiles JSON.
- Chẩn đoán hệ thống, xuất báo cáo và nhật ký tìm kiếm được.
- Giới hạn dung lượng/số bản backup cùng bộ lọc và sắp xếp plugin.

### Security

- Từ chối RBZ mã hóa, ZIP có đường dẫn traversal và gói vượt giới hạn giải nén.
