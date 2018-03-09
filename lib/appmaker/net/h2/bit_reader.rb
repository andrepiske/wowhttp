module Appmaker::Net::H2
  class BitReader
    attr_accessor :cursor

    def initialize data, start_at=0
      @cursor = start_at
      set_buffer data
    end

    def read_integer
      finish_byte
    end

    def read_string
      h = read_bit
      str_length = read_integer
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
