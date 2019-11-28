# frozen_string_literal: true
module Appmaker
  module Net
    class Server
      attr_reader :clients
      attr_reader :config

      class Configuration
        attr_reader :address, :port

        attr_reader :enable_debug_signaling

        # Allowed HTTP protocols. Must be an array. Valid values are "h2" and "http/1.1"
        # Defaults to all protocols.
        attr_reader :allowed_protocols

        # TCP Connection backlog size.
        attr_reader :backlog_size

        # Size in bytes of the buffer size per connection. Defaults to 16 KiB.
        attr_reader :connection_send_buffer_size

        def initialize address, port, conf
          @address = address
          @port = port
          set_conf conf
          if !conf.keys.empty?
            raise "Unrecognized configuration flags: #{conf.keys.join(', ')}\n\t#{conf}"
          end
        end

        alias_method :enable_debug_signaling?, :enable_debug_signaling

        private

        def set_conf conf
          @enable_debug_signaling = conf.delete(:enable_debug_signaling)

          @allowed_protocols = conf.delete(:allowed_protocols) || ['h2', 'http/1.1']

          @backlog_size = conf.delete(:backlog_size) || 10

          @connection_send_buffer_size = conf.delete(:connection_send_buffer_size) || (16 * 1024)
        end
      end

      def initialize address, port, configuration={}
        @config = Configuration.new(address, port, configuration)

        backend = (RUBY_ENGINE == 'jruby' ? :java : :kqueue)
        @selector = ::NIO::Selector.new(backend)
        @clients = Hash.new
        @lock = Mutex.new
        @signaled = false

        use_debug_signaling = @config.enable_debug_signaling?
        Signal.trap 'INT' do
          if use_debug_signaling
            dump_diagnosis_info
          else
            Debug.info('Got INT signal, shutting down...')
          end
          exit(1) if @signaled
          @signaled = true
        end

        Debug.info("Listening on #{address}:#{port}")
        Debug.info("Using #{@selector.backend} backend")
      end

      def dump_diagnosis_info
        Debug.error('## DIAGNOSIS DUMP BEGIN')
        Debug.error("Has #{@clients.length} clients. Now printing client info:")
        @clients.values.each_with_index do |cli, index|
          Debug.error('## DIAG FOR CLIENT #{index}:')
          cli.dump_diagnosis_info
        end
        Debug.error('## DIAGNOSIS DUMP END')
      end

      def configure_ssl(cert, key, cert_store=nil)
        is_jruby = (RUBY_ENGINE == 'jruby')
        @ssl_ctx = OpenSSL::SSL::SSLContext.new

        @ssl_ctx.key = key
        @ssl_ctx.cert = cert
        @ssl_ctx.cert_store = cert_store if cert_store != nil

        if !is_jruby && @ssl_ctx.respond_to?(:min_version=)
          @ssl_ctx.min_version = OpenSSL::SSL::TLS1_2_VERSION
        else
          @ssl_ctx.ssl_version = :TLSv1_2
        end

        # jruby-openssl does not support ALPN yet
        if !is_jruby
          allowed_protocols = @config.allowed_protocols

          @ssl_ctx.alpn_protocols = allowed_protocols.dup
          @ssl_ctx.alpn_select_cb = lambda do |protocols|
            (allowed_protocols & protocols).first || allowed_protocols[-1]
          end
        else
          @ssl_ctx.npn_protocols = @config.allowed_protocols
        end

        @ssl_ctx
      end

      def start_listening handler_klass
        @handler_klass = handler_klass
        @tcp_server = TCPServer.new @config.address, @config.port
        @selector.register(@tcp_server, :r)
      end

      def run_forever
        loop do
          iterate
          if @signaled && !@config.enable_debug_signaling
            Debug.info("Signaled, exiting loop")
          end
        end
      end

      def iterate
        new_clients = []
        readables = []
        writables = []

        clients = @clients.dup
        @selector.select(@config.backlog_size) do |monitor|
          if TCPServer === monitor.io
            new_clients << monitor.io if monitor.readable?
          elsif TCPSocket === monitor.io
            readables << clients[monitor.io] if monitor.readable?
            writables << clients[monitor.io] if monitor.writable?
          end
        end

        # Debug.info("w=#{writables.length}/r=#{readables.length}/n=#{new_clients.length}/c=#{@clients.keys.length}")

        writables.each &:notify_writeable
        readables.each &:notify_readable
        new_clients.each do |io|
          accept_client_connection(io)
        end
      end

      def register_closed connection
        @lock.synchronize do
          io = connection.monitor.io
          @clients.delete io
          begin
            Debug.info("Closing socket #{io} with closed=#{io.closed?}")
            io.close unless io.closed?
          rescue IOError
          end
        end
      end

      def upgrade_connection_to_h2 connection
        # TODO: check if SSL is enabled. Can't use H2 over non-TLS connections
        fabricator = ConnectionFabricator.new self, @handler_klass

        @lock.synchronize do
          ssl_socket = connection.socket
          monitor = connection.monitor
          h2_connection = fabricator.upgrade_connection_to_h2 monitor, ssl_socket

          @clients[monitor.io] = h2_connection
          h2_connection.go_from_h11_upgrade
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
