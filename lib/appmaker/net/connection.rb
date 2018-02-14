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
          _register_closed unless @closed
          @closed = true
          on_close
        end
      end

      # To be overridden
      def on_close; end

      def notify_readable
        return unless @read_callback && !@closed
        begin
          data = @socket.read_nonblock 1024
        rescue EOFError, Errno::ECONNRESET
          close
        end
        @read_callback[data]
      end

      def notify_writeable
        _attempt_write
      end

      private

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
        rescue IO::WaitWritable
        rescue Errno::EPIPE
          puts("BROKEN PIPE!")
          close
          return
        rescue Errno::EPROTOTYPE
          puts("EPROTOTYPE error")
          close
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

    end
  end
end
