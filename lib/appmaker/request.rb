# frozen_string_literal: true
module Appmaker
  class Request
    extend Forwardable

    attr_accessor :verb
    attr_accessor :path
    # attr_accessor :ordered_headers, :headers_hash
    attr_accessor :headers

    def_delegators :@headers, :ordered_headers, :headers_hash

    def initialize
      # @ordered_headers = []
      # @headers_hash = {}
      @headers = Semantic::HeadersStore.new(:request)
    end

    def idempotent?
      %w(GET HEAD PUT DELETE OPTIONS TRACE).include? verb
    end

    def dump_diagnosis_info
      puts("  Request verb=#{verb}")
      puts("  Path=#{path}")
      headers_hash.each do |key, value|
        puts("  Header '#{key}'='#{value}'")
      end
    end

    def valid?
      return false if !verb_allows_body? && has_body?

      true # TODO: ...
    end

    def has_body?
      headers_hash['transfer-encoding'] != nil || headers_hash['content-length'] != nil
    end

    def verb_allows_body?
      %w(POST PUT PATCH).include? verb
    end
  end
end
