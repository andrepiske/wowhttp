module Appmaker::Net::H2
  class HpackDecoder
    def initialize header_block_data
      @header_block = header_block_data
    end

    def decode_all
      reader = BitReader.new @header_block
      headers = []
      while !reader.eof?
        pair = _read_header reader
        headers << pair
      end
      headers
    end

    private

    def _read_header reader
      kind = _read_header_kind reader
      if kind == 61
        index = reader.finish_byte
        _header_by_index index
      elsif kind == 621 || kind == 622
        index = reader.finish_byte
        key_name = if index == 0
                     reader.read_string
                   else
                     _header_by_index(index)[0]
                   end
        value = reader.read_string
        [key_name, value]
      else
        # TODO: implement other two types :)
        binding.pry
      end
    end

    def _header_by_index index
      if index > _static_list_max_index
        # TODO: fetch from dynamic
        binding.pry
      else
        _static_list[:id_to_pair][index]
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

    def _static_list
      @_compiled_static_list ||= begin
        {
          id_to_pair: Hash[_raw_static_list.map { |id, key, value| [id, [key, value]] }],
          pair_to_id: Hash[_raw_static_list.map { |id, key, value| [[key, value], id] }]
        }
      end
    end

    def _static_list_max_index
      61
    end

    def _raw_static_list
      [
        [1, ':authority', nil],
        [2, ':method', 'GET'],
        [3, ':method', 'POST'],
        [4, ':path', '/'],
        [5, ':path', '/index.html'],
        [6, ':scheme', 'http'],
        [7, ':scheme', 'https'],
        [8, ':status', '200'],
        [9, ':status', '204'],
        [10, ':status', '206'],
        [11, ':status', '304'],
        [12, ':status', '400'],
        [13, ':status', '404'],
        [14, ':status', '500'],
        [15, 'accept-charset', nil],
        [16, 'accept-encoding', 'gzip, deflate'],
        [17, 'accept-language', nil],
        [18, 'accept-ranges', nil],
        [19, 'accept', nil],
        [20, 'access-control-allow-origin', nil],
        [21, 'age', nil],
        [22, 'allow', nil],
        [23, 'authorization', nil],
        [24, 'cache-control', nil],
        [25, 'content-disposition', nil],
        [26, 'content-encoding', nil],
        [27, 'content-language', nil],
        [28, 'content-length', nil],
        [29, 'content-location', nil],
        [30, 'content-range', nil],
        [31, 'content-type', nil],
        [32, 'cookie', nil],
        [33, 'date', nil],
        [34, 'etag', nil],
        [35, 'expect', nil],
        [36, 'expires', nil],
        [37, 'from', nil],
        [38, 'host', nil],
        [39, 'if-match', nil],
        [40, 'if-modified-since', nil],
        [41, 'if-none-match', nil],
        [42, 'if-range', nil],
        [43, 'if-unmodified-since', nil],
        [44, 'last-modified', nil],
        [45, 'link', nil],
        [46, 'location', nil],
        [47, 'max-forwards', nil],
        [48, 'proxy-authenticate', nil],
        [49, 'proxy-authorization', nil],
        [50, 'range', nil],
        [51, 'referer', nil],
        [52, 'refresh', nil],
        [53, 'retry-after', nil],
        [54, 'server', nil],
        [55, 'set-cookie', nil],
        [56, 'strict-transport-security', nil],
        [57, 'transfer-encoding', nil],
        [58, 'user-agent', nil],
        [59, 'vary', nil],
        [60, 'via', nil],
        [61, 'www-authenticate', nil]
      ]
    end
  end
end
