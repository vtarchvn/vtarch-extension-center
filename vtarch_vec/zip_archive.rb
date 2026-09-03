# frozen_string_literal: true

# Bộ đọc ZIP nhỏ gọn, chỉ dùng Ruby/Zlib đi kèm SketchUp. Mục đích là xem và
# giải nén RBZ an toàn, không phụ thuộc gem bên thứ ba.
require 'zlib'

module VTARCH
  module VEC
    module ZipArchive
      MAX_ENTRIES = 2_000
      MAX_UNCOMPRESSED_BYTES = 100 * 1024 * 1024

      Entry = Struct.new(:name, :method, :flags, :compressed_size, :size, :offset)

      module_function

      def entries(path)
        data = File.binread(path)
        # EOCD nằm trong 65,557 byte cuối file. rindex không truyền vị trí để
        # tìm từ cuối; truyền vị trí thấp sẽ chỉ kiểm tra phần đầu archive.
        eocd_at = data.rindex([0x06054b50].pack('V'))
        raise 'Gói RBZ không phải ZIP hợp lệ.' unless eocd_at && eocd_at >= [data.bytesize - 65_557, 0].max
        bytes = data.byteslice(eocd_at, 22)
        raise 'EOCD ZIP bị hỏng.' unless bytes && bytes.bytesize == 22
        header = bytes.unpack('VvvvvVVv')
        raise 'EOCD ZIP không nằm ở cuối archive.' unless eocd_at + 22 + header[7] == data.bytesize
        count, directory_size, directory_offset = header[4], header[5], header[6]
        raise 'Gói RBZ có quá nhiều file.' if count > MAX_ENTRIES
        raise 'Central directory không hợp lệ.' if directory_offset + directory_size > data.bytesize

        cursor = directory_offset
        total_size = 0
        list = count.times.map do
          values = data.byteslice(cursor, 46).unpack('VvvvvvvVVVvvvvvVV')
          raise 'Central directory bị hỏng.' unless values && values[0] == 0x02014b50
          name_length, extra_length, comment_length = values[10], values[11], values[12]
          name = data.byteslice(cursor + 46, name_length).force_encoding('UTF-8')
          entry = Entry.new(name, values[4], values[3], values[8], values[9], values[16])
          validate_entry(entry)
          total_size += entry.size
          raise 'Gói RBZ vượt giới hạn 100 MB sau giải nén.' if total_size > MAX_UNCOMPRESSED_BYTES
          cursor += 46 + name_length + extra_length + comment_length
          entry
        end
        list
      rescue Zlib::Error, ArgumentError => e
        raise "Không thể đọc RBZ: #{e.message}"
      end

      def extract(path, destination, selected_entries = entries(path))
        data = File.binread(path)
        selected_entries.each do |entry|
          next if entry.name.end_with?('/')
          target = File.join(destination, entry.name)
          raise 'Đường dẫn giải nén không an toàn.' unless inside?(destination, target)
          FileUtils.mkdir_p(File.dirname(target))
          File.binwrite(target, decode_entry(data, entry))
        end
      end

      def validate_entry(entry)
        raise 'RBZ được mã hóa không được hỗ trợ.' unless (entry.flags & 1).zero?
        raise "RBZ chứa đường dẫn không an toàn: #{entry.name}" unless safe_path?(entry.name)
        raise "Kiểu nén không được hỗ trợ: #{entry.name}" unless [0, 8].include?(entry.method)
      end

      def safe_path?(name)
        normalized = name.tr('\\\\', '/')
        !normalized.empty? && !normalized.start_with?('/') && !normalized.match?(%r{(^|/)\.\.(/|$)}) && !normalized.match?(%r{^[A-Za-z]:})
      end

      def inside?(root, target)
        File.expand_path(target).start_with?(File.expand_path(root) + File::SEPARATOR)
      end

      def decode_entry(data, entry)
        local = data.byteslice(entry.offset, 30).unpack('VvvvvvVVVvv')
        raise 'Local header không hợp lệ.' unless local && local[0] == 0x04034b50
        name_length, extra_length = local[9], local[10]
        payload_at = entry.offset + 30 + name_length + extra_length
        payload = data.byteslice(payload_at, entry.compressed_size)
        raise 'Dữ liệu RBZ bị thiếu.' unless payload && payload.bytesize == entry.compressed_size
        content = entry.method.zero? ? payload : Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(payload)
        raise 'Kích thước file RBZ không hợp lệ.' unless content.bytesize == entry.size
        content
      end
    end
  end
end
