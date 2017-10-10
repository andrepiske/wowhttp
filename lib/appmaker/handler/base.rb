# frozen_string_literal: true
module Appmaker
  module Handler
    class Base
      def initialize http_connection, request
        @http_connection = http_connection
        @request = request
      end

      def make_base_response
        resp = Appmaker::Response.new

        resp.set_header 'Server', 'lolmao'
        resp.set_header 'Date', DateTime.now.rfc2822
        resp.set_header 'Connection', 'close'

        resp
      end

      def respond_with_generic_not_found
        resp = make_base_response
        resp.code = 404
        respond_with_content resp, 'Content not found', 'text/plain'
      end

      def respond_with_content response, content, mime_type
        data = if content.encoding == Encoding::ASCII_8BIT
                 content
               else
                 content.b
               end
        response.set_header 'Content-Length', data.length
        response.set_header 'Content-Type', mime_type

        @http_connection.write response.full_header
        @http_connection.write data do
          @http_connection.close
        end
      end

      def call
        self
      end

      def closed
        @http_connection = nil
      end
    end
  end
end
