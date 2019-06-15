# frozen_string_literal: true
module Appmaker
  module Net
    class Http2Connection < Connection
      attr_accessor :settings
      attr_accessor :window_size # flow-control window size
      attr_accessor :recv_window_size # flow-control window size for receiving data

      def initialize *args
        @request_handler_fabricator = args.pop
        @settings = {
          SETTINGS_HEADER_TABLE_SIZE: 4096,
          SETTINGS_ENABLE_PUSH: 1,
          SETTINGS_MAX_CONCURRENT_STREAMS: 100,
          SETTINGS_INITIAL_WINDOW_SIZE: 65536,
          SETTINGS_MAX_FRAME_SIZE: 16384,
          SETTINGS_MAX_HEADER_LIST_SIZE: 2**16
        }
        @hpack_local_context = H2::HpackContext.new 4096
        @hpack_remote_context = H2::HpackContext.new 4096
        @h2streams = {}
        @recv_window_size = 65536 # Initial windows size according to RFC
        @window_size = @settings[:SETTINGS_INITIAL_WINDOW_SIZE]
        super *args
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

      def go! preface_sent: false
        # We must send a SETTINGS frame before anything else, as per RFC:
        #   The server connection preface consists of a potentially empty
        #   SETTINGS frame (Section 6.5) that MUST be the first frame the server
        #   sends in the HTTP/2 connection.
        _send_initial_settings

        @frame_reader = Appmaker::Net::Http2StreamingBuffer.new(preface_sent) do |hframe|
          _handle_h2_frame hframe
        end

        read do |data|
          @frame_reader.feed data
        end
      end

      def make_frame type, bit_writer, sid: 0, flags: 0
        payload = bit_writer == nil ? '' : bit_writer.bytes_array
        H2::Frame.new(type, flags, payload.length, sid, payload)
      end

      def mark_stream_closed sid
        @h2streams.delete sid
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

      def send_frame frame, &block
        # TODO: refactor and move this table out of here
        int_frame_type = {
          :DATA => 0x00,
          :HEADERS => 0x01,
          :PRIORITY => 0x02,
          :RST_STREAM => 0x03,
          :SETTINGS => 0x04,
          :PUSH_PROMISE => 0x05,
          :PING => 0x06,
          :GOAWAY => 0x07,
          :WINDOW_UPDATE => 0x08
        }[frame.type]

        writer = H2::BitWriter.new
        raise "Announced frame payload length is different from actual payload" if frame.payload_length != frame.payload.length
        writer.write_int24 frame.payload_length
        writer.write_byte int_frame_type
        writer.write_byte frame.flags
        # writer.write_byte 0 # Stream identifier (R + finish first byte)
        writer.write_int32 frame.stream_identifier
        writer.write_bytes frame.payload

        frame_data = writer.bytes_array

        if frame.type == :HEADERS && frame_data.length >= 16384 # 16KiB
          Debug.warn("WARNING: Sending header frame over 16KiB (#{frame_data.length}B)")
        end

        write frame_data, &block
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

      def get_or_create_stream sid
        stream = @h2streams[sid]
        if stream == nil
          stream = Http2Stream.new(sid, self, @request_handler_fabricator)
          stream.window_size = @settings[:SETTINGS_INITIAL_WINDOW_SIZE]
          @h2streams[sid] = stream
        end
        stream
      end

      def _send_initial_settings
        frame = make_frame :SETTINGS, nil
        send_frame frame do
          Debug.info("First SETTINGS sent")
        end
      end

      def _handle_h2_frame fr
        Debug.info("Received frame #{fr.type}")

        unavailable_type = [:PUSH_PROMISE, :CONTINUATION]
        if unavailable_type.include?(fr.type)
          Debug.error("ERROR: Don't know how to process frame")
          binding.pry
        end

        method_name = "_handle_h2_#{fr.type.to_s.downcase}_frame"
        send(method_name, fr)
      end

      def _handle_h2_priority_frame fr
        reader = H2::BitReader.new fr.payload
        # FIXME: no-op for now
      end

      def _handle_h2_ping_frame fr
        reader = H2::BitReader.new fr.payload
        ack_frame = H2::Frame.new(:PING, 1, 8, 0, fr.payload)
        send_frame ack_frame
        Debug.info("responding to ping request")
      end

      def _handle_h2_rst_stream_frame fr
        reader = H2::BitReader.new fr.payload
        error_code = reader.read_int32
        Debug.warn("Got RST_STREAM with error code #{error_code}") unless error_code == 0x08 # 8 = CANCEL
        stream = @h2streams[fr.stream_identifier]
        stream.on_rst_stream unless stream == nil
      end

      def _handle_h2_goaway_frame fr
        reader = H2::BitReader.new fr.payload
        last_stream_id = (reader.read_int32 & 0x7FFFFFFF) # gotta remove the R bit
        error_code = reader.read_int32

        error_symbol = error_codes.find { |code, sym| code == error_code }
        error_message = fr.payload[(reader.cursor / 8)..-1].pack('C*')
        Debug.error("Handled GOWAY error #{error_symbol} with message: \n#{error_message}")
        Debug.error("Dumping diagnosis info:")
        dump_diagnosis_info
      end

      def _handle_h2_window_update_frame fr
        reader = H2::BitReader.new(fr.payload)
        increment = (reader.read_int32 & 0x7FFFFFFF)

        if fr.stream_identifier == 0
          Debug.info("Window size increment: #{increment} for the connection")
          change_window_size_by increment
        else
          stream = @h2streams[fr.stream_identifier]
          if stream
            Debug.info("Window size increment: #{increment} for stream #{fr.stream_identifier}")
            stream.change_window_size_by increment
          end
        end
        turn_gears
      end

      def _handle_h2_data_frame fr
        reader = H2::BitReader.new fr.payload
        stream = @h2streams[fr.stream_identifier]
        end_stream = (fr.flags & 0x01) == 0x01

        @recv_window_size -= fr.payload_length
        Debug.info("Global recv window size = #{@recv_window_size}")
        if @recv_window_size < 128000
          increment = 524288 - @recv_window_size
          @recv_window_size += increment

          if increment > 0
            Debug.info("Sending increment of #{increment / 1024}kb, WS=#{@recv_window_size}")
            bw = H2::BitWriter.new
            bw.write_int32 increment
            send_frame H2::Frame.new(:WINDOW_UPDATE, 0, 4, 0, bw.bytes)
          end
        end

        if stream != nil
          stream.recv_window_size -= fr.payload_length
          Debug.info("Stream #{fr.stream_identifier} recv window size = #{stream.recv_window_size}") if Debug.info?
          if stream.recv_window_size < 128000
            increment = 524288 - stream.recv_window_size
            stream.recv_window_size += increment

            if increment > 0
              Debug.info("Sending increment of #{increment / 1024}kb, WS=#{@recv_window_size} stream=#{fr.stream_identifier}") if Debug.info?
              bw = H2::BitWriter.new
              bw.write_int32 increment
              send_frame H2::Frame.new(:WINDOW_UPDATE, 0, 4, fr.stream_identifier, bw.bytes)
            end
          end
        end

        if stream == nil # TODO: should do a better check here
          Debug.warn "Discarding DATA frame as stream #{fr.stream_identifier} is no more"
          return
        end

        stream.receive_data fr.payload.pack('C*'), end_stream
      end

      def _handle_h2_headers_frame fr
        flag_end_stream = (fr.flags & 0x01) != 0
        flag_end_headers = (fr.flags & 0x04) != 0
        flag_padded = (fr.flags & 0x08) != 0
        flag_priority = (fr.flags & 0x20) != 0
        hb_index = 0
        hb_index += 1 if flag_padded
        hb_index += 5 if flag_priority

        header_data = fr.payload[hb_index..-1]
        decoder = H2::HpackDecoder.new(header_data, @hpack_remote_context)
        headers = decoder.decode_all

        str_flags = {
          'end_stream' => flag_end_stream,
          'end_headers' => flag_end_headers,
          'padded' => flag_padded,
          'priority' => flag_priority
        }.select { |k, v| v }.map { |k, v| k }.join(',')

        if Debug.info?
          Debug.info("Reader headers with flags=#{str_flags}:")
          headers.each do |name, value|
            Debug.info("\t#{name} => #{value}")
          end
        end

        stream = get_or_create_stream fr.stream_identifier
        stream.receive_headers headers, flags: {
          end_stream: flag_end_stream,
          end_headers: flag_end_headers,
          padded: flag_padded,
          priority: flag_priority
        }
      end

      def _h2_settingtype_to_sym id
        {
          0x01 => :SETTINGS_HEADER_TABLE_SIZE,
          0x02 => :SETTINGS_ENABLE_PUSH,
          0x03 => :SETTINGS_MAX_CONCURRENT_STREAMS,
          0x04 => :SETTINGS_INITIAL_WINDOW_SIZE,
          0x05 => :SETTINGS_MAX_FRAME_SIZE,
          0x06 => :SETTINGS_MAX_HEADER_LIST_SIZE,
        }[id]
      end

      def _handle_h2_settings_frame fr
        is_ack = ((fr.flags & 1) == 1)
        if is_ack
          Debug.info "Client ACK-ed our SETTINGS frame"
          return
        end

        num_params = fr.payload_length / 6
        (0...num_params).each do |idx|
          offset = idx * 6
          id = fr.payload[offset...offset+2].pack('C*').unpack('S>')[0]
          value = fr.payload[offset+2...offset+6].pack('C*').unpack('I>')[0]
          settings[_h2_settingtype_to_sym(id)] = value
        end
        Debug.info("Got some settings for stream #{fr.stream_identifier}, sending ACK") if Debug.info?

        if @settings[:SETTINGS_INITIAL_WINDOW_SIZE] != @window_size
          @window_size = @settings[:SETTINGS_INITIAL_WINDOW_SIZE]
          Debug.info("Initial window size changed to = #{@window_size}")
        end

        ack_frame = H2::Frame.new(:SETTINGS, 1, 0, 0, '')
        send_frame ack_frame
      end
    end
  end
end
