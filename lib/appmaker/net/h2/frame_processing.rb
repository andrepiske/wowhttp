# frozen_string_literal: true

module Appmaker
  module Net
    module H2::FrameProcessing
      include H2::Handlers::PriorityFrame
      include H2::Handlers::PingFrame
      include H2::Handlers::RstFrame
      include H2::Handlers::ContinuationFrame
      include H2::Handlers::DataFrame
      include H2::Handlers::GoawayFrame
      include H2::Handlers::HeadersFrame
      include H2::Handlers::SettingsFrame
      include H2::Handlers::WindowUpdateFrame

      def setup_h2_frame_reader preface_sent
        @frame_reader = Appmaker::Net::Http2StreamingBuffer.new(preface_sent, &method(:handle_h2_frame))
      end

      # Called when data was read from the socket
      def feed_h2_data data
        @frame_reader.feed data

        if @frame_reader.error?
          terminate_connection :PROTOCOL_ERROR
        end
      end

      private

      def handle_h2_frame fr
        Debug.info("Received frame #{fr.type} stream=#{fr.stream_identifier}")

        if fr.payload_length > @settings[:SETTINGS_MAX_FRAME_SIZE]
          return terminate_connection :FRAME_SIZE_ERROR
        end

        unavailable_type = [:PUSH_PROMISE]
        if unavailable_type.include?(fr.type)
          Debug.error("ERROR: Don't know how to process frame of type #{fr.type}")
          return terminate_connection :INTERNAL_ERROR
        end

        if !@awaiting_continuation_for && fr.type == :HEADERS
          if (fr.flags & 0x04) == 0
            @awaiting_continuation_for = fr.stream_identifier
          end
        elsif @awaiting_continuation_for
          if fr.type != :CONTINUATION && fr.stream_identifier != @awaiting_continuation_for
            Debug.info("Expected CONTINUATION frame for #{@awaiting_continuation_for}, but got #{fr.type} for #{fr.stream_identifier}")
            return terminate_connection :PROTOCOL_ERROR
          else
            @awaiting_continuation_for = nil if (fr.flags & 0x04) != 0
          end
        end

        if !%i(CONTINUATION RST_STREAM).include?(fr.type) && stream = @h2streams[fr.stream_identifier]
          if %i(open idle half_closed_remote).include?(stream.state) && stream.header_state == :partial
            Debug.info("Expected CONTINUATION frame, but got #{fr.type}")
            return terminate_connection :PROTOCOL_ERROR
          end
        end

        if fr.type == :UNSUPPORTED
          Debug.info("Got frame of unsupported type, discarding")
          return
        end

        sid = fr.stream_identifier
        if sid > 0 && ![:HEADERS, :PRIORITY, :WINDOW_UPDATE].include?(fr.type)
          stream = @h2streams[sid]
          if !stream || stream.state == :closed
            Debug.info("Got frame for closed stream (#{sid}), terminating")
            return terminate_connection :PROTOCOL_ERROR
          end
        end

        method_name = "handle_h2_#{fr.type.to_s.downcase}_frame"
        send(method_name, fr)
      end

      def add_header_block_fragment_to_stream stream, fragment, flags
        result = stream.add_header_block_fragment fragment, flags: flags

        if result == :invalid_state
          terminate_connection :PROTOCOL_ERROR
        elsif result == :hpack_error
          terminate_connection :COMPRESSION_ERROR
        end
      end
    end
  end
end
