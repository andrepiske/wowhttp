# frozen_string_literal: true
module Appmaker::Net::H2
  class BitReader
    attr_accessor :cursor

    def initialize data, start_at=0
      @cursor = start_at
      set_buffer data
    end

    def read_integer prefix
      value = finish_byte
      if value == (1 << prefix) - 1
        m = 0
        loop do
          b = read_byte
          value += (b & 127) * (2 ** m)
          m += 7
          break if (b & 128 != 128)
        end
      end
      value
    end

    def read_string
      h = read_bit
      str_length = read_integer 7
      bytes = read_bytes str_length
      if h == 1 # if it is huffman coded, then decode it
        StringDecoder.decode_string bytes
      else
        bytes.pack('C*').force_encoding('ASCII-8BIT')
      end
    end

    def eof?
      @cursor >= @buffer.length * 8
    end

    def read_byte
      read_bytes(1)[0]
    end

    def read_int32
      d = read_bytes 4
      (d[0] << 24) + (d[1] << 16) + (d[2] << 8) + d[3]
    end

    def read_int24
      d = read_bytes 3
      (d[0] << 16) + (d[1] << 8) + d[2]
    end

    def read_bit
      index = @cursor / 8
      bit_index = @cursor % 8
      @cursor += 1
      (@buffer[index] & (128 >> bit_index)) > 0 ? 1 : 0
    end

    def read_bytes n
      index = @cursor / 8
      @cursor += 8 * n + ((@cursor - (8 % 8)) % 8)
      @buffer[index...(index+n)]
    end

    def finish_byte
      # TODO: check bounds?
      index = @cursor / 8
      mask = (1 << (8 - (@cursor % 8))) - 1
      value = @buffer[index] & mask
      @cursor += 8 - (@cursor % 8)
      value
    end

    def back n
      @cursor -= n
    end

    def reset
      @cursor = 0
    end

    private

    def set_buffer data
      if data.is_a?(String)
        @buffer = data.unpack('C*')
      else # if it already is an array
        @buffer = data
      end
    end
  end
end
