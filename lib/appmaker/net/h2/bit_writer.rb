# frozen_string_literal: true
module Appmaker::Net::H2
  class BitWriter
    attr_accessor :cursor

    def initialize
      @cursor = 0
      @buffer = []
    end

    def bytes_array
      bytes.pack('C*')
    end

    def bytes
      @buffer
    end

    def write_byte by
      (0...8).each do |index|
        write_bit(by & (128 >> index))
      end
    end

    def finish_byte by
      remaining_bits = 8 - (@cursor % 8)
      (remaining_bits - 1).downto(0).each do |index|
        write_bit((by >> index) & 1)
      end
    end

    def write_bit b
      index = @cursor / 8
      bit_index = @cursor % 8
      @buffer << 0 if index >= @buffer.length
      by = @buffer[index]
      by |= (128 >> bit_index) if b > 0
      @buffer[index] = by
      @cursor += 1
    end

    def write_int16 value
      write_byte((value >> 8) & 0xFF)
      write_byte(value & 0xFF)
    end

    def write_int24 value
      write_byte((value >> 16) & 0xFF)
      write_byte((value >> 8) & 0xFF)
      write_byte(value & 0xFF)
    end

    def write_int32 value
      write_byte((value >> 24) & 0xFF)
      write_byte((value >> 16) & 0xFF)
      write_byte((value >> 8) & 0xFF)
      write_byte(value & 0xFF)
    end

    def write_prefixed_int value, prefix
      limit = (1 << prefix)
      if value < limit
        finish_byte value
      else
        finish_byte(limit - 1) # fill with 1's
        while value >= 128
          write_byte((value % 128) + 128)
          value = value / 128
        end
        write_byte value
      end
    end

    # TODO: this one is for binary data
    def write_bytes value
      value = value.unpack('C*') if value.is_a?(String)
      @buffer += value
      @cursor += value.length
    end

    def write_string value
      # TODO: optimize
      write_bit 0
      write_prefixed_int value.length, 7

      # raise 'TODO: Unsupported string beyond 127bytes' if value.length >= 127
      value.unpack('C*').each do |byte|
        write_byte byte
      end
    end
  end
end
