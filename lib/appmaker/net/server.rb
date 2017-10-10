# frozen_string_literal: true
module Appmaker
  module Net
    class Server

      def initialize address, port
        @address, @port = address, port
        @selector = ::NIO::Selector.new
        @clients = Hash.new
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
        @selector.select do |monitor|
          if TCPServer === monitor.io
            accept_client_connection monitor.io if monitor.readable?
          elsif TCPSocket === monitor.io && monitor.readable?
            @clients[monitor.io.fileno].notify_readable
          elsif TCPSocket === monitor.io && monitor.writable?
            @clients[monitor.io.fileno].notify_writeable
          end
        end
      end

      def register_write_intention connection
        # FIXME: better handle this
        # @selector.register connection.socket, :w
      end

      def register_read_intention connection
        @selector.register connection.socket, :rw
      end

      def register_closed connection
        @selector.deregister connection.socket
        @clients.delete connection.socket.fileno

        connection.socket.close
      end

      private

      def accept_client_connection io
        client_socket = io.accept_nonblock exception: false
        return if client_socket == :wait_readable

        fd = client_socket.fileno
        @clients[fd] = Appmaker::Net::HttpConnection.new self, client_socket, @handler_klass
      end

    end
  end
end
