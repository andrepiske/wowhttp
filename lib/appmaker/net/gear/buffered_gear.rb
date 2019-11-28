# frozen_string_literal: true
module Appmaker::Net
  module Gear
    class BufferedGear
      attr_accessor :sink
      attr_accessor :buffer_size

      def initialize buffer_size, &sink
        @sink = sink
        @buffer_size = buffer_size
        @buffer = []
      end

      def tap
        method(:tap_proc)
      end

      private

      def tap_proc limit, send_proc
        @send_proc = send_proc
        @limit = limit
        if @buffer.empty?
          @sink.call(@buffer_size, method(:send_proc_block))
        else
          flush
        end
      end

      def send_proc_block content, finished:
        return flush if @finished

        @finished = finished

        @buffer << content.b if content && content.length > 0
        flush
      end

      def flush
        if @buffer.empty?
          @send_proc.call(nil, finished: true) if @finished
          return
        end

        buf = @buffer.shift
        if buf.length <= @limit
          @send_proc.call buf, finished: (@finished && @buffer.empty?)
        else
          buf_send = buf[0...@limit]
          @buffer.unshift buf[@limit..-1]
          @send_proc.call buf_send, finished: false
        end
      end
    end
  end
end
