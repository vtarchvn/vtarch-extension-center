# VTARCH Plugin Store

`catalog.json` là danh mục được VEC tải qua HTTPS. Mỗi plugin cần có `id`, `name`, `version`, `downloadUrl` (HTTPS) và `sha256` của file `.rbz`.

Ví dụ:

```json
{
  "id": "vtarch.sample",
  "name": "VTARCH Sample",
  "version": "1.0.0",
  "author": "VTARCH",
  "description": "Mô tả ngắn.",
  "downloadUrl": "https://github.com/vtarchvn/vtarch-extension-center/releases/download/v1.0.0/VTARCH_SAMPLE.rbz",
  "sha256": "64-ky-tu-hex-sha256-cua-file-rbz"
}
```
