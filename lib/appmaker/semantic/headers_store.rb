# frozen_string_literal: true
module Appmaker
  module Semantic
    # Common header store for both requests and responses
    class HeadersStore
      class MissingHeaderError < StandardError; end

      # headers as they have been received. Untransformed and in order
      attr_reader :ordered_headers

      # headers, indexed. All keys are lower case
      attr_reader :headers_hash

      # either :request or :response
      attr_accessor :kind

      def initialize kind=nil
        @kind = kind
        @ordered_headers = []
        @headers_hash = {}
      end

      def fetch key, default_value=nil
        value = @headers_hash.fetch(key.downcase, default_value)
        return value unless value == nil
        return yield(key) if block_given?
        nil
      end

      def get! key
        value = fetch key
        raise MissingHeaderError.new(key) if value == nil
        value
      end

      def add_header key, value
        @ordered_headers << [key, value]
        @headers_hash[key.downcase] = value
      end

      def set_header key, value
        key_lower = key.downcase
        if @kind == :response && key_lower == 'set-cookie'
          add_header key, value
        else
          @headers_hash[key_lower] = value
          oh_index = @ordered_headers.find_index { |k, v| k.downcase == key_lower }
          if oh_index
            @ordered_headers[oh_index][1] = value
          else
            @ordered_headers << [key, value]
          end
        end
      end
    end
  end
end
