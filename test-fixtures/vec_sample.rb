# frozen_string_literal: true

require 'sketchup.rb'

module VTARCH
  module VECSample
    unless file_loaded?(__FILE__)
      UI.menu('Extensions').add_item('VEC Sample RB') { UI.messagebox('VEC sample .rb đang hoạt động.') }
      file_loaded(__FILE__)
    end
  end
end
