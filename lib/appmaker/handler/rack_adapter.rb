# frozen_string_literal: true
require 'stringio'
require 'marcel'

module Appmaker
  module Handler
    class RackAdapter < Base
      def self.request_to_env(request)
        protocol_version = request.protocol.upcase
        host, port = request.host_with_port

        hijack_proc = proc do |*args|
          Debug.error("Not implemented: hijack!")
          binding.pry
          Debug.error("Done hijacking")
        end

        env = {
          'GATEWAY_INTERFACE' => 'CGI/1.2',
          'SERVER_PROTOCOL' => protocol_version,
          'REQUEST_METHOD' => request.verb.to_s,
          'REQUEST_PATH' => request.path_info,
          'REQUEST_URI' => request.path,
          'PATH_INFO' => request.path_info,

           # FIXME: get real remote address
          'REMOTE_ADDR' => request.remote_address,

           # FIXME: get real server name
          'SERVER_NAME' => host,
          'SERVER_PORT' => port,

          'rack.version' => ::Rack::VERSION,
          'rack.input' => StringIO.new,
          'rack.errors' => $stderr,
          'rack.output' => $stdout,
          'rack.url_scheme' => 'https',
          'rack.multithread' => false,
          'rack.multiprocess' => false,
          'rack.run_once' => false,
          'rack.hijack?' => true,
          'rack.hijack' => hijack_proc
        }

        # HTTP specifics
        request.ordered_headers.each do |name, value|
          key_name = name.tr('-', '_').upcase
          env["HTTP_#{key_name}"] = value
        end

        # binding.pry
        env['HTTP_VERSION'] = protocol_version

        env
      end
    end
  end
end

<<-FOOBAR

"REQUEST_PATH"=>"/employer/account_active_sub_statuses",
"REQUEST_URI"=>"/employer/account_active_sub_statuses?foo=qux&bar=2948",
"HTTP_VERSION"=>"HTTP/1.1",
"HTTP_HOST"=>"dev.jobscore.com:3000",
"HTTP_CONNECTION"=>"keep-alive",
"HTTP_CACHE_CONTROL"=>"max-age=0",
"HTTP_UPGRADE_INSECURE_REQUESTS"=>"1",
"HTTP_USER_AGENT"=>"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36",
"HTTP_ACCEPT"=>"text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8",
"HTTP_ACCEPT_ENCODING"=>"gzip, deflate",
"HTTP_ACCEPT_LANGUAGE"=>"en-US,en;q=0.9",

"SERVER_NAME"=>"dev.jobscore.com",
"SERVER_PORT"=>"3000",
"PATH_INFO"=>"/employer/account_active_sub_statuses",
"REMOTE_ADDR"=>"127.0.0.1",
"puma.socket"=>#<TCPSocket:fd 17>,
"rack.hijack?"=>true,

FOOBAR
