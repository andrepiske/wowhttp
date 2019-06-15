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

      attr_reader :socket, :monitor, :server

      def initialize server, monitor, socket
        @closed = false
        @server = server
        @monitor = monitor
        @socket = socket
        @lock = Mutex.new

        @read_callback = nil
        @reading_buffer = []
        @writing_buffer = []
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
        more_to_read = false
        loop do
          return unless @read_callback && !@closed
          begin
            how_much = 1024
            data = @socket.read_nonblock how_much
            more_to_read = true if data.length == how_much
          rescue OpenSSL::SSL::SSLErrorWaitReadable
            return
          rescue EOFError, Errno::ECONNRESET
            close
          rescue OpenSSL::OpenSSLError => e
            Debug.error("SSL Error (class=#{e.class}) with message='#{e.message}'")
            close
          end
          @read_callback[data] unless @closed

          break unless more_to_read
        end
      end

      def notify_writeable
        on_writeable
        _attempt_write
      end

      # Overridable
      def has_write_intention?
        @writing_buffer.length > 0
      end

      private

      # To be overridden
      def on_close; end

      # To be overridden
      def on_writeable; end

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
          written_length = @socket.write_nonblock data
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
          if @socket.closed?
            locked ? _close_without_locking : close
            return
          else
            raise
          end
        rescue IO::WaitWritable
        rescue Errno::EPIPE
          Debug.error("BROKEN PIPE!")
          locked ? _close_without_locking : close
          return
        rescue Errno::EPROTOTYPE
          Debug.error("EPROTOTYPE error")
          locked ? _close_without_locking : close
          return
        ensure
          @lock.unlock if locked
        end

        write_intention = has_write_intention? || has_remaining_data
        if !@closed
          if write_intention
            _register_write_intention
          else
            @monitor.remove_interest :w
          end
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
    end
  end
end
