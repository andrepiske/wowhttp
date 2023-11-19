# frozen_string_literal: true
# require 'fcntl'
require 'excon'

module Appmaker
  module Handler
    class ReverseProxy < Base
      def initialize options, *args
        super *args
        @proxy_to = options[:proxy_to]
        @buffer_size = options.fetch(:buffer_size, 16 * 1024)
        @hooks = options.fetch(:hooks, {})
      end

      def handle_request
        if Debug.info?
          Debug.info("Want proxy path #{@proxy_to}: (#{@request.verb} #{@request.path})")
          Debug.info("Headers: #{@request.ordered_headers}")
        end

        proxy_path = call_hook(:path_transform, request.path)

        proxy_conn = Excon.new(@proxy_to)
        proxy_resp = proxy_conn.request(method: @request.verb, path: proxy_path)

        proxy_resp = call_hook(:post_proxy, proxy_resp)

        response = make_base_response
        response.code = proxy_resp.status

        proxy_resp.headers.each do |name, value|
          next if ::Appmaker::Response.forbidden_header?(name)
          response.set_header name.b, value.b
        end

        @http_connection.send_header response
        @http_connection.write_then_finish proxy_resp.body
      end

      private

      def transform_path
        # no-op for now
        request.path
      end

      def call_hook(hook_name, datum)
        hook = @hooks[hook_name]
        return datum unless hook != nil
        hook.call(request, datum)
      end
    end
  end
end
