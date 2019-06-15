# frozen_string_literal: true
module Appmaker
  class StackHandler
    def initialize
    end

    def call
    end

    def handle_request
    end

    def closed
      @http_connection = nil
      Debug.info("Connection closed")
    end

    def self.new_handler *args
      k = args.pop
      if Class === k
        k.new *args
      elsif Proc === k || (k != nil && k.respond_to?(:call))
        k.call *args
      end
    end
  end
end
