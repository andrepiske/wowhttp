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
  end
end
