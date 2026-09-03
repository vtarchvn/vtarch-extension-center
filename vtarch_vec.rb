# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module VTARCH
  module VEC
    EXTENSION_NAME = 'VTARCH Extension Center'
    EXTENSION_VERSION = '1.1.1'
  end
end

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new(
    VTARCH::VEC::EXTENSION_NAME,
    'vtarch_vec/main'
  )
  extension.description = 'Quản lý, sao lưu và khôi phục plugin SketchUp (.rb và .rbz).'
  extension.version = VTARCH::VEC::EXTENSION_VERSION
  extension.creator = 'VTARCH'
  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
