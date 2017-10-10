# frozen_string_literal: true
module Appmaker
  module Net
    class LineStreamingBuffer
      attr_reader :buffer

      def initialize &emit_callback
        @emit_callback = emit_callback
        @finished = false
        @buffer = []
      end

      def feed buffer
        @buffer += buffer.chars
        _flush
      end

      def finish
        @finished = true
      end

      def _flush
        loop do
          return if @finished
          endline_pos = @buffer.index("\n")
          return unless endline_pos
          line = @buffer[0...endline_pos].join
          @buffer = @buffer[endline_pos+1..-1]
          @emit_callback[line]
        end
      end
    end

    class CharStreamingBuffer
      def initialize &emit_callback
        @emit_callback = emit_callback
      end

      def feed data
        _emit_buffer data.chars
      end

      private

      def _emit_buffer buffer
        buffer.each do |ch|
          @emit_callback[ch]
        end
      end
    end
  end
end
