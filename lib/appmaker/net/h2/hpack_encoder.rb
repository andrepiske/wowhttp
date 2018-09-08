# frozen_string_literal: true
module Appmaker::Net::H2
  class HpackEncoder
    attr_reader :ctx

    def initialize writer, ctx
      @writer = writer
      @ctx = ctx
    end

    def dump response
      # @writer.write_bit 1
      # @writer.finish_byte 8 # 8 => [8, ':status', '200'] from static list
      @writer.write_byte 0x10
      @writer.write_string ':status'
      @writer.write_string response.code.to_s

      # always produce 6.2.2.
      response.headers.each do |name, value|
        header_name = name.downcase.to_s

        # XXX: Section 8.1.2.2 forbids us from sending Connection headers
        # so let's drop them silently.
        next if header_name == 'connection'

        @writer.write_byte 0x10
        @writer.write_string header_name
        @writer.write_string value.to_s
      end
    end
  end
end
