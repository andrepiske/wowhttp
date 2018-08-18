# frozen_string_literal: true
module Appmaker::Net::H2
  class HpackContext
    attr_reader :max_dynamic_size

    def initialize max_dynamic_size
      @dynamic_list = []
      @max_dynamic_size = max_dynamic_size
    end

    def static_list_max_index
      61
    end

    def static_list
      @static_list ||= begin
        {
          id_to_pair: Hash[raw_static_list.map { |id, key, value| [id, [key, value]] }],
          pair_to_id: Hash[raw_static_list.map { |id, key, value| [[key, value], id] }]
        }
      end
    end

    def fetch index
      return static_list[:id_to_pair][index] if index <= static_list_max_index
      @dynamic_list[index - static_list_max_index - 1]
    end

    def insert_in_dynamic key_name, value
      @dynamic_list.unshift [key_name.downcase.to_s, value.to_s]
      @dynamic_list.slice! @max_dynamic_size if @dynamic_list.length > @max_dynamic_size
    end

    def resize_dynamic_table new_max_size
    end

    def raw_static_list

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
