# frozen_string_literal: true
module Appmaker
  module Net
    class Server
      def initialize address, port
        @address, @port = address, port
        @selector = ::NIO::Selector.new(:kqueue)
        @clients = Hash.new
        @lock = Mutex.new

        puts("Using #{@selector.backend} backend")
      end

      def configure_ssl(cert, key, cert_store=nil)
        @ssl_ctx = OpenSSL::SSL::SSLContext.new :TLSv1_2_server

        @ssl_ctx.key = key
        @ssl_ctx.cert = cert
        @ssl_ctx.cert_store = cert_store if cert_store != nil

        @ssl_ctx.alpn_protocols = ['http/1.1', 'h2']
        @ssl_ctx.alpn_select_cb = lambda do |protocols|
          'h2'
          # 'http/1.1'
        end
      end

      def start_listening handler_klass
        @handler_klass = handler_klass
        @tcp_server = TCPServer.new @address, @port
        @selector.register(@tcp_server, :r)
      end

      def run_forever
        loop do
          iterate
        end
      end

      def iterate
        new_clients = []
        readables = []
        writeables = []

        clients = @clients.dup
        @selector.select do |monitor|
          if TCPServer === monitor.io
            new_clients << monitor.io if monitor.readable?
          elsif TCPSocket === monitor.io && monitor.readable?
            readables << clients[monitor.io]
          elsif TCPSocket === monitor.io && monitor.writable?
            writeables << clients[monitor.io]
          end
        end

        writeables.each &:notify_writeable
        readables.each &:notify_readable
        new_clients.each { |io| accept_client_connection(io) }
      end

      def register_closed connection
        @lock.synchronize do
          io = connection.socket
          @clients.delete io
          begin
            io.close unless io.closed?
          rescue IOError
          end
        end
      end

      private

      def accept_client_connection io
        client_socket = io.accept_nonblock exception: false
        return if client_socket == :wait_readable

        connection = nil
        @lock.synchronize do
          monitor = @selector.register(client_socket, :r)
          connection = Appmaker::Net::HttpConnection.new self, monitor, @handler_klass
          connection.use_ssl(@ssl_ctx) if @ssl_ctx
          @clients[client_socket] = connection
        end

        connection.process_request
      end
    end
  end
end
