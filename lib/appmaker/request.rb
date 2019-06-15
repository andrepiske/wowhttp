# frozen_string_literal: true
module Appmaker
  class Request
    extend Forwardable

    attr_accessor :verb
    attr_accessor :path
    # attr_accessor :ordered_headers, :headers_hash
    attr_accessor :headers
    attr_accessor :protocol, :remote_address

    def_delegators :@headers, :ordered_headers, :headers_hash

    def initialize
      # @ordered_headers = []
      # @headers_hash = {}
      @headers = Semantic::HeadersStore.new(:request)
    end

    def idempotent?
      %w(GET HEAD PUT DELETE OPTIONS TRACE).include? verb
    end

    def safe?
      %w(GET HEAD OPTIONS).include? verb
    end

    def host_with_port
      result = headers_hash['host']&.split(':')
      return nil if result == nil
      result << 443 if result.length < 2
      result
    end

    def host
      h = host_with_port
      return nil if h == nil
      h[0]
    end

    def port
      h = host_with_port
      return nil if h == nil
      h[1]
    end

    def dump_diagnosis_info
      Debug.error("  Request verb=#{verb}")
      Debug.error("  Path=#{path}")
      headers_hash.each do |key, value|
        Debug.error("  Header '#{key}'='#{value}'")
      end
    end

    def path_info
      separator = path.index '?'
      return path if separator == nil
      path[0...separator]
    end

    def query_string
      separator = path.index '?'
      return nil if separator == nil
      path[separator+1..-1]
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
