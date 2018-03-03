# frozen_string_literal: true
module Appmaker
  module Net
    class Connection
      class Chunk
        attr_accessor :data

        def initialize data, &finished
          @data = data
          @finished_callback = finished
        end

        def notify_finished *args
          @finished_callback.call(*args) unless @finished_callback == nil
        end
      end

      attr_reader :socket, :server

      def initialize server, monitor
        @closed = false
        @server = server
        @monitor = monitor
        @socket = monitor.io
        @use_ssl = false
        @lock = Mutex.new

        @read_callback = nil
        @reading_buffer = []
        @writing_buffer = []
      end

      def use_ssl ssl_ctx
        @ssl_ctx = ssl_ctx
        @use_ssl = true

        @ssl_socket = ::OpenSSL::SSL::SSLSocket.new(@socket, @ssl_ctx)
        @ssl_socket.sync_close = true

        # FIXME: Use accept_nonblock instead
        @ssl_socket.accept
        # proto = @ssl_socket.alpn_protocol
      end

      def write data, &finished
        chunk = Chunk.new(data, &finished)
        @lock.synchronize do
          @writing_buffer << chunk
        end
        _attempt_write
      end

      def read &callback_proc
        @read_callback = callback_proc
        _register_read_intention
      end

      def close
        @lock.synchronize do
          _close_without_locking
        end
      end

      def notify_readable
        return unless @read_callback && !@closed
        begin
          data = _iosocket.read_nonblock 1024
        rescue EOFError, Errno::ECONNRESET
          close
        end
        @read_callback[data]
      end

      def notify_writeable
        _attempt_write
      end

      private

      # To be overridden
      def on_close; end

      def _close_without_locking
        _register_closed unless @closed
        @closed = true
        on_close
      end

      def _attempt_write
        locked = true
        unless @lock.try_lock
          # If we're not acquiring the lock, let at least
          # announce that we want to write, so new attempts
          # will be automatically made by the reactor.
          _register_write_intention
          return
        end

        if @writing_buffer.length == 0
          @lock.unlock
          return
        end

        has_remaining_data = true

        begin
          chunk = @writing_buffer[0]
          data = chunk.data
          wanted_length = data.length
          written_length = _iosocket.write_nonblock data
          if written_length < wanted_length
            pending_data = data[written_length..-1]
            chunk.data = pending_data
          else
            @writing_buffer.shift
            @lock.unlock
            locked = false
            has_remaining_data = false
            chunk.notify_finished
          end
        rescue IOError
          if _iosocket.closed?
            locked ? _close_without_locking : close
            return
          else
            raise
          end
        rescue IO::WaitWritable
        rescue Errno::EPIPE
          puts("BROKEN PIPE!")
          locked ? _close_without_locking : close
          return
        rescue Errno::EPROTOTYPE
          puts("EPROTOTYPE error")
          locked ? _close_without_locking : close
          return
        ensure
          @lock.unlock if locked
        end

        if has_remaining_data && !@closed
          _register_write_intention
        elsif !has_remaining_data && !@closed
          @monitor.remove_interest :w
        end
      end

      def _register_closed
        @monitor.close true
        @server.register_closed self
      end

      def _register_write_intention
        @monitor.add_interest :w
      end

      def _register_read_intention
        @monitor.add_interest :r
      end

      def _iosocket
        if @use_ssl
          @ssl_socket
        else
          @socket
        end
      end
    end
  end
end
