# frozen_string_literal: true
require 'arraybuffer'

module Appmaker::Net::H2
  class BitWriter
    # Buffer size is slightly above 16k so resizing is less likely to happen
    INITIAL_BUFFER_SIZE = 16896

    attr_accessor :cursor

    def initialize
      @cursor = 0
      @capacity = INITIAL_BUFFER_SIZE
      @buffer = ArrayBuffer.new(@capacity)
      @view = DataView.new(@buffer)
    end

    def bytes_array
      buffer_size = (@cursor >> 3)
      buffer_size += 1 if (@cursor & 3) > 0
      @buffer.bytes[0...buffer_size]
    end

    alias bytes bytes_array

    def write_byte value
      grow_buffer_by(1) if (@cursor >> 3) + 1 >= @capacity
      @view.setU8(@cursor >> 3, value)
      @cursor += 8
    end

    def finish_byte by
      remaining_bits = 8 - (@cursor % 8)
      (remaining_bits - 1).downto(0).each do |index|
        write_bit((by >> index) & 1)
      end
    end

    def grow_buffer_by incr
      if (@cursor >> 3) + incr >= @capacity
        @buffer.realloc(@buffer.size + INITIAL_BUFFER_SIZE)
        @view.size = @buffer.size
        @capacity = @buffer.size
      end
    end

    def write_bit b
      grow_buffer_by(1) if (@cursor >> 3) + 1 >= @capacity

      index = @cursor / 8
      bit_index = @cursor % 8
      by = @buffer[index]
      by |= (128 >> bit_index) if b > 0
      @buffer[index] = by
      @cursor += 1
    end

    def write_int16 value
      grow_buffer_by(2) if (@cursor >> 3) + 2 >= @capacity
      @view.setU16(@cursor >> 3, value)
      @cursor += 16
    end

    def write_int24 value
      grow_buffer_by(3) if (@cursor >> 3) + 3 >= @capacity
      @view.setU24(@cursor >> 3, value)
      @cursor += 24
    end

    def write_int32 value
      grow_buffer_by(4) if (@cursor >> 3) + 4 >= @capacity
      @view.setU32(@cursor >> 3, value)
      @cursor += 32
    end

    def write_prefixed_int value, prefix
      limit = (1 << prefix)
      if value < limit
        finish_byte value
      else
        finish_byte(limit - 1) # fill with 1's
        value -= (limit - 1)
        while value >= 128
          write_byte((value % 128) + 128)
          value = value / 128
        end
        write_byte value
      end
    end

    def write_bytes value
      length = value.length
      cursor = @cursor >> 3
      grow_buffer_by(length) if cursor + length >= @capacity
      @view.setBytes(cursor, value)

      @cursor += (length << 3)
    end

    def write_string value
      write_bit 0
      write_prefixed_int value.length, 7

      write_bytes value
    end
  end
end
