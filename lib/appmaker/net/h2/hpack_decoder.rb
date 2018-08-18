# frozen_string_literal: true
module Appmaker::Net::H2
  class HpackDecoder
    attr_reader :ctx

    def initialize header_block_data, ctx
      @ctx = ctx
      @header_block = header_block_data
    end

    def decode_all
      reader = BitReader.new @header_block
      headers = []
      while !reader.eof?
        pair = parse_header reader
        headers << pair unless pair == nil
      end
      headers
    end

    private

    def parse_header reader
      kind = _read_header_kind reader
      if kind == 61
        index = reader.read_integer 7
        @ctx.fetch index
      elsif kind == 621 || kind == 622 || kind == 623
        index = reader.read_integer(kind == 621 ? 6 : 4)
        key_name = if index == 0
                     reader.read_string
                   else
                     @ctx.fetch(index)[0]
                   end
        value = reader.read_string
        @ctx.insert_in_dynamic(key_name, value) if kind == 621
        [key_name, value]
      elsif kind == 63
        new_max_size = reader.read_integer 5
        @ctx.resize_dynamic_table new_max_size
        nil
      end
    end

    def _read_header_kind reader
      if reader.read_bit == 1
        # 1 X X X X X X -> 6.1.  Indexed Header Field Representation
        61
      else
        # 6.2.  Literal Header Field Representation
        if reader.read_bit == 1
          # 0 1 X X X X X -> 6.2.1.  Literal Header Field with Incremental Indexing
          621
        else
          if reader.read_bit == 1
            # 0 0 1 X X X X -> 6.3.  Dynamic Table Size Update
            63
          else
            if reader.read_bit == 1
              # 0 0 0 1 X X X -> 6.2.3.  Literal Header Field Never Indexed
              623
            else
              # 0 0 0 0 X X X -> 6.2.2.  Literal Header Field without Indexing
              622
            end
          end
        end
      end
    end
  end
end
