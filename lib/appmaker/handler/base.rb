# frozen_string_literal: true
module Appmaker
  module Handler
    class Base
      attr_reader :http_connection, :request

      def initialize http_connection, request
        @http_connection = http_connection
        @request = request
      end

      def keepalive!
        @http_connection.set_keepalive true
      end

      def do_not_keepalive!
        @http_connection.set_keepalive false
      end

      def set_async!
        @http_connection.set_async!
      end

      def on_receive_data_chunk data, is_final
        # do nothing, you have to override this if you want to
      end

      def make_base_response
        resp = Appmaker::Response.new

        resp.set_header 'Server', 'lolmao'
        resp.set_header 'Date', DateTime.now.rfc2822
        resp.set_header 'Accept-CH', 'device-memory, dpr, width, viewport-width, rtt, downlink, ect'
        resp.set_header 'Accept-CH-Lifetime', '300'

        if @http_connection.recycle
          resp.set_header 'Connection', 'keep-alive'
        else
          resp.set_header 'Connection', 'close'
        end

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

        @http_connection.send_header response
        @http_connection.write_then_finish data
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
