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

    class Http2StreamingBuffer
      EXPECTED_PREFACE = [0x50,0x52,0x49,0x20,0x2a,0x20,0x48,0x54,0x54,0x50,0x2f,0x32,0x2e,0x30,0x0d,0x0a,0x0d,0x0a,0x53,0x4d,0x0d,0x0a,0x0d,0x0a].freeze

      attr_reader :error

      def initialize preface_sent, &emit_callback
        @emit_callback = emit_callback
        @state = preface_sent ? :read_frame_header : :hope_for_preface
        @buffer = []
        @error = nil
      end

      def feed data
        send "_feed_#{@state}", data
      end

      def error?
        @error != nil
      end

      private

      def _feed_error data
        nil
      end

      def _feed_hope_for_preface data
        bytes = data.bytes
        @buffer += bytes
        if @buffer.length >= 24
          if @buffer[0...24] == EXPECTED_PREFACE
            @buffer = @buffer[24..-1]
            @state = :read_frame_header
          else
            @error = :protocol_error
            @state = :error
          end

          _backfeed
        end
      end

      def _frame_type_name type
        {
          0x00 => :DATA,
          0x01 => :HEADERS,
          0x02 => :PRIORITY,
          0x03 => :RST_STREAM,
          0x04 => :SETTINGS,
          0x05 => :PUSH_PROMISE,
          0x06 => :PING,
          0x07 => :GOAWAY,
          0x08 => :WINDOW_UPDATE,
          0x09 => :CONTINUATION
        }.fetch(type, :UNSUPPORTED)
      end

      def _feed_read_frame_header data
        @buffer += data.bytes
        if @buffer.length >= 9
          header = @buffer[0...9]
          payload_length = ([0] + header[0...3]).pack('C*').unpack('I>')[0]
          frame_type = _frame_type_name(header[3])
          frame_flags = header[4]
          stream_identifier = header[5..-1].pack('C*').unpack('I>')[0]
          reserved_bit = (stream_identifier & 2147483648 != 0)
          stream_identifier &= 0x7FFF_FFFF if reserved_bit
          @frame = H2::Frame.new(frame_type, frame_flags, payload_length, stream_identifier, nil, reserved_bit)
          @buffer = @buffer[9..-1]

          if payload_length > 0
            @state = :reading_frame
          else
            _emit_frame @frame
          end
          _backfeed
        end
      end

      def _feed_reading_frame data
        @buffer += data.bytes
        if @buffer.length >= @frame.payload_length
          payload_length = @frame.payload_length
          @frame.payload = @buffer[0...payload_length]
          _emit_frame @frame
          @state = :read_frame_header
          @frame = nil
          @buffer = @buffer[payload_length..-1]
          _backfeed
        end
      end

      def _backfeed
        feed(''.encode 'ASCII-8BIT')
      end

      def _emit_frame frame
        if frame.type != nil
          @emit_callback.call frame
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
