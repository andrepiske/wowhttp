# frozen_string_literal: true
module Appmaker
  module Net
    class Http2Connection < Connection
      FRAME_TYPE_MAP = {
        :DATA => 0x00,
        :HEADERS => 0x01,
        :PRIORITY => 0x02,
        :RST_STREAM => 0x03,
        :SETTINGS => 0x04,
        :PUSH_PROMISE => 0x05,
        :PING => 0x06,
        :GOAWAY => 0x07,
        :WINDOW_UPDATE => 0x08
      }.freeze

      include H2::FrameProcessing

      attr_accessor :settings
      attr_accessor :window_size # flow-control window size
      attr_accessor :recv_window_size # flow-control window size for receiving data

      def initialize *args
        @request_handler_fabricator = args.pop
        @settings = {
          SETTINGS_HEADER_TABLE_SIZE: 4096,
          SETTINGS_ENABLE_PUSH: 1,
          SETTINGS_MAX_CONCURRENT_STREAMS: 100,
          SETTINGS_INITIAL_WINDOW_SIZE: 65535,
          SETTINGS_MAX_FRAME_SIZE: 16384,
          SETTINGS_MAX_HEADER_LIST_SIZE: 2**16
        }
        @hpack_local_context = H2::HpackContext.new 4096
        @hpack_remote_context = H2::HpackContext.new 4096
        @h2streams = {}
        @closed_h2streams = Set.new
        @recv_window_size = 65535 # Initial windows size according to RFC
        @window_size = @settings[:SETTINGS_INITIAL_WINDOW_SIZE]
        @greatest_remote_sid = -1
        super *args
      end

      def mon_h2streams_length
        @h2streams.length
      end
      def mon_closed_h2streams
        @closed_h2streams.length
      end

      def dump_diagnosis_info
        Debug.error("HTTP/2 connection in state=#{@state}")
        Debug.error("Settings = #{@settings}")
        Debug.error("Has #{@h2streams.length} streams")
        Debug.error("Now dumping streams:")
        @h2streams.values.each do |s|
          s.dump_diagnosis_info
        end
      end

      def register_gear gear
        _register_write_intention unless @closed
      end

      def go_from_h11_upgrade
        Debug.info('Going from HTTP/1.1 to H2')
        go! preface_sent: true
      end

      # Client is connected, let's start receiving data from them
      def go! preface_sent: false
        # We must send a SETTINGS frame before anything else, as per RFC:
        #   The server connection preface consists of a potentially empty
        #   SETTINGS frame (Section 6.5) that MUST be the first frame the server
        #   sends in the HTTP/2 connection.
        send_initial_settings

        setup_h2_frame_reader preface_sent

        read(&method(:feed_h2_data))
      end

      def make_frame type, bit_writer, sid: 0, flags: 0
        payload = bit_writer == nil ? '' : bit_writer.bytes_array
        H2::Frame.new(type, flags, payload.length, sid, payload, false)
      end

      def mark_stream_closed sid
        @h2streams.delete sid

        @closed_h2streams << sid if sid >= @greatest_remote_sid
        @closed_h2streams.delete_if do |sid|
          sid < @greatest_remote_sid
        end
      end

      # Terminates due to some error
      # This will send a goaway with the given reason and terminate the connection
      # (and therefore all streams)
      def terminate_connection reason
        Debug.info("Terminating connection, reason=#{reason}")
        send_goaway reason do
          close
        end
      end

      def send_goaway reason
        if Symbol === reason
          reason = error_codes.find { |_,name| name == reason }.first
        end

        last_stream_id = @h2streams.keys.max || 0

        writer = H2::BitWriter.new
        writer.write_int32(last_stream_id & 0x7FFFFFFF)
        writer.write_int32 reason
        frame = make_frame :GOAWAY, writer
        send_frame frame do
          yield if block_given?
        end
      end

      def send_rst_stream sid
        stream = @h2streams[sid]
        writer = H2::BitWriter.new
        writer.write_int32 0x08 # CANCEL
        frame = make_frame :RST_STREAM, writer
        send_frame frame do
          mark_stream_closed sid
        end
      end

      def send_data_frame content, end_stream, stream_identifier, &block
        writer = H2::BitWriter.new
        writer.write_int24 content.length
        writer.write_byte 0 # DATA
        writer.write_byte (end_stream ? 1 : 0)
        writer.write_int32 stream_identifier

        if content.length > @settings[:SETTINGS_MAX_FRAME_SIZE]
          Debug.error("Frame payload too large")
          binding.pry
        end

        Debug.info("\tsend DATA frame of size #{content.length} (limit #{@settings[:SETTINGS_MAX_FRAME_SIZE]})")
        change_window_size_by(-content.length)

        write_multi [writer.bytes, content], &block
      end

      def send_frame frame, &block
        int_frame_type = FRAME_TYPE_MAP[frame.type]

        writer = H2::BitWriter.new
        if frame.payload_length != frame.payload.length
          fr = frame
          raise "Announced frame payload length is different from actual payload"
        end
        writer.write_int24 frame.payload_length
        writer.write_byte int_frame_type
        writer.write_byte frame.flags
        writer.write_int32 frame.stream_identifier

        if frame.payload_length > @settings[:SETTINGS_MAX_FRAME_SIZE]
          Debug.error("Frame payload too large")
          binding.pry
        end

        frame_data = writer.bytes_array
        if frame.type == :DATA
          Debug.info("\tsend DATA frame of size #{frame.payload_length} (limit #{@settings[:SETTINGS_MAX_FRAME_SIZE]})")
          change_window_size_by(-frame.payload_length)
        end

        if frame.type == :HEADERS && (frame_data.length + frame.payload_length) >= 16384 # 16KiB
          Debug.warn("WARNING: Sending header frame over 16KiB (#{frame_data.length + frame.payload_length}B)")
        end

        if frame.payload_length > 0
          write_multi [frame_data, frame.payload], &block
        else
          write frame_data, &block
        end
      end

      def error_codes
        [
          [0x00, :NO_ERROR], # The associated condition is not a result of an error.  For example, a GOAWAY might include this code to indicate graceful shutdown of a connection.
          [0x01, :PROTOCOL_ERROR], # The endpoint detected an unspecific protocol error.  This error is for use when a more specific error code is not available.
          [0x02, :INTERNAL_ERROR], # The endpoint encountered an unexpected internal error.
          [0x03, :FLOW_CONTROL_ERROR], # The endpoint detected that its peer violated the flow-control protocol.
          [0x04, :SETTINGS_TIMEOUT], # The endpoint sent a SETTINGS frame but did not receive a response in a timely manner.  See Section 6.5.3 ("Settings Synchronization").
          [0x05, :STREAM_CLOSED], # The endpoint received a frame after a stream was half-closed.
          [0x06, :FRAME_SIZE_ERROR], # The endpoint received a frame with an invalid size.
          [0x07, :REFUSED_STREAM], # The endpoint refused the stream prior to performing any application processing (see Section 8.1.4 for details).
          [0x08, :CANCEL], # Used by the endpoint to indicate that the stream is no longer needed.
          [0x09, :COMPRESSION_ERROR], # The endpoint is unable to maintain the header compression context for the connection.
          [0x0a, :CONNECT_ERROR], # The connection established in response to a CONNECT request (Section 8.3) was reset or abnormally closed.
          [0x0b, :ENHANCE_YOUR_CALM], # The endpoint detected that its peer is exhibiting a behavior that might be generating excessive load.
          [0x0c, :INADEQUATE_SECURITY], # The underlying transport has properties that do not meet minimum security requirements (see Section 9.2).
          [0x0d, :HTTP_1_1_REQUIRED] # The endpoint requires that HTTP/1.1 be used instead of HTTP/2.
        ]
      end

      def on_writeable
        turn_gears
      end

      def has_write_intention?
        return true if super
        @h2streams.values.any?(&:intents_to_write?)
      end

      def change_window_size_by delta
        @window_size += delta
      end

      private

      def on_close
        Debug.info("CONNECTION H2 CLOSED")
        streams = @h2streams.map { |sid, stream| stream }
        streams.each(&:on_rst_stream)
      end

      def turn_gears
        remaining = 0
        @h2streams.each do |sid, stream|
          remaining += 1 if stream.intents_to_write?
          stream.turn_gear
        end

        remaining
      end

      def close_all_idle_streams_before sid
        to_close = @h2streams.values.select do |stream|
          stream.state == :idle && stream.sid < sid
        end
        to_close.each(&:mark_finished)
      end

      # Get or create a remote-initiated stream
      # Does not apply when the server creates a stream (e.g. a push promise)
      def get_or_create_stream sid
        return nil unless (sid & 1) == 1
        return nil if sid_was_closed?(sid)

        created = false
        stream = @h2streams[sid]

        if !stream
          stream = Http2Stream.new(sid, self, @request_handler_fabricator)
          stream.window_size = @settings[:SETTINGS_INITIAL_WINDOW_SIZE]
          stream.hpack_context = @hpack_remote_context
          @h2streams[sid] = stream

          @greatest_remote_sid = sid
          created = true

          close_all_idle_streams_before sid
        end

        return created, stream
      end

      def sid_was_closed? sid
        sid < @greatest_remote_sid || @closed_h2streams.include?(sid)
      end

      def send_initial_settings
        frame = make_frame :SETTINGS, nil

        send_frame frame do
          Debug.info("First SETTINGS sent")
        end
      end
    end
  end
end
