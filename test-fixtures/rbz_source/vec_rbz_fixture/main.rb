# frozen_string_literal: true

require 'sketchup.rb'

module VTARCH
  module VECRBZFixture
    unless file_loaded?(__FILE__)
      UI.menu('Extensions').add_item('VEC Sample RBZ') { UI.messagebox('VEC sample .rbz đang hoạt động.') }
      file_loaded(__FILE__)
    end
  end
end
