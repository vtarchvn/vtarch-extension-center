# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'tmpdir'
require 'zlib'
require_relative '../vtarch_vec/zip_archive'

class ZipArchiveTest < Minitest::Test
  def test_reads_and_extracts_a_safe_archive
    Dir.mktmpdir do |directory|
      archive = File.join(directory, 'sample.rbz')
      write_stored_zip(archive, 'sample_plugin.rb', 'puts :vec_test')

      entries = VTARCH::VEC::ZipArchive.entries(archive)
      assert_equal ['sample_plugin.rb'], entries.map(&:name)

      destination = File.join(directory, 'output')
      VTARCH::VEC::ZipArchive.extract(archive, destination, entries)
      assert_equal 'puts :vec_test', File.read(File.join(destination, 'sample_plugin.rb'))
    end
  end

  def test_rejects_path_traversal
    Dir.mktmpdir do |directory|
      archive = File.join(directory, 'unsafe.rbz')
      write_stored_zip(archive, '../evil.rb', 'puts :no')
      assert_raises(RuntimeError) { VTARCH::VEC::ZipArchive.entries(archive) }
    end
  end

  private

  # Tạo ZIP "stored" nhỏ cho unit test, không dùng gem zip bên thứ ba.
  def write_stored_zip(path, name, content)
    crc = Zlib.crc32(content)
    local = [0x04034b50, 20, 0, 0, 0, 0, crc, content.bytesize, content.bytesize, name.bytesize, 0].pack('VvvvvvVVVvv') + name + content
    central = [0x02014b50, 20, 20, 0, 0, 0, 0, crc, content.bytesize, content.bytesize, name.bytesize, 0, 0, 0, 0, 0, 0].pack('VvvvvvvVVVvvvvvVV') + name
    eocd = [0x06054b50, 0, 0, 1, 1, central.bytesize, local.bytesize, 0].pack('VvvvvVVv')
    File.binwrite(path, local + central + eocd)
  end
end
