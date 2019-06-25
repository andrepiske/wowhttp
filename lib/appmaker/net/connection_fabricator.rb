# frozen_string_literal: true
module Appmaker
  module Net
    class ConnectionFabricator
      Error = Class.new(StandardError)
      InvalidALPNProtocolError = Class.new(Error)
      SSLError = Class.new(Error)

      def initialize server, handler_klass
        @handler_klass = handler_klass
        @server = server
      end

      def fabricate_connection monitor, ssl_ctx
        use_ssl = (ssl_ctx != nil)
        socket = monitor.io

        # We don't support HTTP2 over non-secure
        return _fabricate_http_connection(monitor, socket) unless use_ssl

        ssl_socket = ::OpenSSL::SSL::SSLSocket.new socket, ssl_ctx
        ssl_socket.sync_close = true

        # FIXME: Use accept_nonblock instead
        ssl_socket.accept
        if RUBY_ENGINE == 'jruby'
          proto = 'http/1.1'
        else
          proto = ssl_socket.alpn_protocol
        end

        case proto
        when 'h2'
          _fabricate_http2_connection monitor, ssl_socket
        when 'http/1.1'
          _fabricate_http_connection monitor, ssl_socket
        else
          raise InvalidALPNProtocolError, "Unknown ALPN protocol: '#{proto}'. Rejecting connection."
        end
      rescue Errno::ECONNRESET => e
        raise Error, "ECONNRESET"
      rescue OpenSSL::OpenSSLError => e
        raise SSLError, "OpenSSLError: #{e.class} message=#{e.message}"
      end

      def upgrade_connection_to_h2 monitor, ssl_socket
        _fabricate_http2_connection monitor, ssl_socket
      end

      private

      def _fabricate_http2_connection monitor, socket
        Appmaker::Net::Http2Connection.new @server, monitor, socket, @handler_klass
      end

      def _fabricate_http_connection monitor, socket
        Appmaker::Net::HttpConnection.new @server, monitor, socket, @handler_klass
      end
    end
  end
end
