# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new('VEC Sample RBZ', 'vec_rbz_fixture/main')
  extension.description = 'Plugin mẫu để kiểm thử cài, backup và khôi phục RBZ trong VEC.'
  extension.version = '1.0.0'
  extension.creator = 'VTARCH'
  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
