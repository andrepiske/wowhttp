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

      attr_reader :socket

      def initialize server, socket
        @closed = false
        @server = server
        @socket = socket
        @read_callback = nil
        @reading_buffer = []
        @writing_buffer = []
      end

      def write data, &finished
        @writing_buffer << Chunk.new(data, &finished)
        _attempt_write
      end

      def read &callback_proc
        @read_callback = callback_proc
        _register_read_intention
      end

      def close
        _register_closed unless @closed
        @closed = true
      end

      def notify_readable
        return unless @read_callback && !@closed
        begin
          data = @socket.read_nonblock 16
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
        return if @writing_buffer.length == 0

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
        end

        _register_write_intention
      end

      def _register_closed
        @server.register_closed self
      end

      def _register_write_intention
        return if @reggg
        @reggg = true
        @server.register_write_intention self
      end

      def _register_read_intention
        @server.register_read_intention self
      end

    end
  end
end
