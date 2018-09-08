# frozen_string_literal: true
module Appmaker
  module Net
    class Server
      def initialize address, port
        @address, @port = address, port

        backend = (RUBY_ENGINE == 'jruby' ? :java : :kqueue)
        @selector = ::NIO::Selector.new(backend)
        @clients = Hash.new
        @lock = Mutex.new
        @signaled = false

        Signal.trap 'INT' do
          dump_diagnosis_info
          exit(1) if @signaled
          @signaled = true
        end

        puts("Using #{@selector.backend} backend")
      end

      def dump_diagnosis_info
        puts('## DIAGNOSIS DUMP BEGIN')
        puts("Has #{@clients.length} clients. Now printing client info:")
        @clients.values.each_with_index do |cli, index|
          puts('## DIAG FOR CLIENT #{index}:')
          cli.dump_diagnosis_info
        end
        puts('## DIAGNOSIS DUMP END')
      end

      def configure_ssl(cert, key, cert_store=nil)
        @ssl_ctx = OpenSSL::SSL::SSLContext.new :TLSv1_2_server

        @ssl_ctx.key = key
        @ssl_ctx.cert = cert
        @ssl_ctx.cert_store = cert_store if cert_store != nil

        allowed_protocolos = ['h2', 'http/1.1']

        @ssl_ctx.alpn_protocols = allowed_protocolos.dup
        @ssl_ctx.alpn_select_cb = lambda do |protocols|
          (allowed_protocolos & protocols).first
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
          # break if @signaled
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
        binding.pry if @signaled

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

        fabricator = ConnectionFabricator.new self, @handler_klass

        connection = nil
        @lock.synchronize do
          monitor = @selector.register(client_socket, :r)
          begin
            connection = fabricator.fabricate_connection monitor, @ssl_ctx
          rescue ConnectionFabricator::Error
            @selector.deregister(client_socket)
            begin
              monitor.close unless monitor.closed?
            rescue IOError
            end
          else
            @clients[client_socket] = connection
          end
        end

        connection.go! unless connection == nil
      end
    end
  end
end
