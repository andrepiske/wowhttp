module Appmaker::Net
  module H2
    HpackError = Class.new(StandardError)
    HpackDecoderError = Class.new(HpackError)
  end
end

require 'appmaker/net/h2/frame'
require 'appmaker/net/h2/hpack_context'
require 'appmaker/net/h2/hpack_decoder'
require 'appmaker/net/h2/hpack_encoder'
require 'appmaker/net/h2/bit_reader'
require 'appmaker/net/h2/bit_writer'
require 'appmaker/net/h2/string_decoder'
require 'appmaker/net/h2/handlers'
require 'appmaker/net/h2/frame_processing'
