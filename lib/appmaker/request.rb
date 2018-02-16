# frozen_string_literal: true
module Appmaker
  class Request
    attr_accessor :verb
    attr_accessor :path
    attr_accessor :ordered_headers, :headers_hash

    def initialize
      @ordered_headers = []
      @headers_hash = {}
    end

    def idempotent?
      %w(GET HEAD PUT DELETE OPTIONS TRACE).include? verb
    end

    def valid?
      return false if !verb_allows_body? && has_body?

      true # TODO: ...
    end

    def has_body?
      @headers_hash['transfer-encoding'] != nil || @headers_hash['content-length'] != nil
    end

    def verb_allows_body?
      %w(POST PUT PATCH).include? verb
    end
  end
end
