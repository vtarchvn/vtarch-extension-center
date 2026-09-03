# Release checklist

## Trước khi tạo tag

- [ ] Chạy toàn bộ checklist trong `docs/TESTING.md` trên SketchUp 2021+.
- [ ] Kiểm tra phiên bản trong `vtarch_vec.rb`, README và CHANGELOG khớp nhau.
- [ ] Đóng gói RBZ: file `vtarch_vec.rb` và thư mục `vtarch_vec/` phải nằm ở gốc archive.
- [ ] Tạo SHA-256 cho `VTARCH_VEC.rbz`.
- [ ] Đảm bảo working tree sạch và mọi thay đổi đã được push.

## GitHub Release

- [ ] Tạo tag `v1.0.0` từ nhánh `main`.
- [ ] Tạo Release với ghi chú từ CHANGELOG.
- [ ] Đính kèm `VTARCH_VEC.rbz` và tệp checksum.
- [ ] Kiểm tra tải file từ trang Release và cài thử trên SketchUp sạch.
