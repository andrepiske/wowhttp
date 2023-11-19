# frozen_string_literal: true
module Appmaker
  module Net
    module Net::H2::FrameProcessing
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

      def handle_h2_priority_frame fr
        if fr.stream_identifier == 0
          Debug.info "Got PRIORITY for stream 0, terminating"
          return terminate_connection :PROTOCOL_ERROR
        end
        if fr.payload_length != 5
          Debug.info "Got PRIORITY with invalid payload size (#{fr.payload_length}), terminating"
          return terminate_connection :FRAME_SIZE_ERROR
        end

        reader = H2::BitReader.new fr.payload
        parse_priority_frame_payload(reader, fr)
      end

      def parse_priority_frame_payload(reader, fr)
        dependency = reader.read_int32
        exclusive = (dependency & 0x1000_000 != 0)
        dependency &= 0x7FFF_FFFF
        weight = reader.read_byte

        if dependency == fr.stream_identifier
          Debug.info "PRIORITY: Stream can't depend on itself, terminating"
          terminate_connection :PROTOCOL_ERROR
          return false
        end

        # binding.pry

        # FIXME: no-op for now

        return true
      end

      def handle_h2_ping_frame fr
        if fr.payload_length != 8
          Debug.info "Got PING with invalid payload size (#{fr.payload_length}), terminating"
          return terminate_connection :FRAME_SIZE_ERROR
        end

        is_ack = ((fr.flags & 1) == 1)
        if is_ack
          Debug.info("Ignoring PING with ACK flag set")
          return
        end

        reader = H2::BitReader.new fr.payload
        ack_frame = H2::Frame.new(:PING, 1, 8, 0, fr.payload, false)
        send_frame ack_frame
        Debug.info("responding to ping request")
      end

      def handle_h2_rst_stream_frame fr
        reader = H2::BitReader.new fr.payload
        error_code = reader.read_int32
        Debug.warn("Got RST_STREAM with error code #{error_code}") unless error_code == 0x08 # 8 = CANCEL
        sid = fr.stream_identifier
        stream = @h2streams[sid]
        if stream
          return terminate_connection(:PROTOCOL_ERROR) if stream.state == :idle

          stream.on_rst_stream
        else
          terminate_connection(:PROTOCOL_ERROR) unless sid_was_closed?(sid)
        end
      end

      def handle_h2_goaway_frame fr
        reader = H2::BitReader.new fr.payload
        last_stream_id = (reader.read_int32 & 0x7FFFFFFF) # gotta remove the R bit
        error_code = reader.read_int32

        error_symbol = error_codes.find { |code, sym| code == error_code }
        error_message = fr.payload[(reader.cursor / 8)..-1].pack('C*')
        Debug.error("Handled GOWAY error #{error_symbol} with message: \n#{error_message}")
        Debug.error("Dumping diagnosis info:")
        dump_diagnosis_info
      end

      def handle_h2_window_update_frame fr
        reader = H2::BitReader.new(fr.payload)

        if fr.payload_length != 4
          Debug.info("Frame size #{fr.payload_length} is invalid for window_update frame, terminating")
          return terminate_connection :FRAME_SIZE_ERROR
        end

        increment = (reader.read_int32 & 0x7FFFFFFF)

        if increment == 0
          Debug.info("Got window_update with 0 increase, terminating")
          return terminate_connection :PROTOCOL_ERROR
        end

        stream = nil

        if fr.stream_identifier == 0
          Debug.info("Window size increment: #{increment} for the connection")
          change_window_size_by increment
        else
          stream = @h2streams[fr.stream_identifier]

          if stream
            Debug.info("Window size increment: #{increment} for stream #{fr.stream_identifier}")

            stream.change_window_size_by increment

            change_window_size_by increment
          else
            return terminate_connection(:PROTOCOL_ERROR) unless sid_was_closed?(fr.stream_identifier)
          end
        end

        # check for max window size
        if (stream && stream.window_size > 2147483647) || (window_size > 2147483647)
          Debug.info("Window size grew too large, terminating")
          return terminate_connection :FLOW_CONTROL_ERROR
        end

        turn_gears
      end

      def handle_h2_data_frame fr
        reader = H2::BitReader.new fr.payload
        stream = @h2streams[fr.stream_identifier]
        end_stream = (fr.flags & 0x01) != 0
        flag_padded = (fr.flags & 0x08) != 0

        if fr.stream_identifier <= 0
          return terminate_connection :PROTOCOL_ERROR
        end

        if sid_was_closed?(fr.stream_identifier)
          return terminate_connection :STREAM_CLOSED
        end

        if !stream || !%i(open half_closed_local).include?(stream.state)
          return terminate_connection :PROTOCOL_ERROR
        end

        if ![:open, :half_closed_remote].include?(stream.state)
          return terminate_connection(:STREAM_CLOSED)
        end

        data = fr.payload
        if flag_padded
          pad_length = fr.payload[0]
          if pad_length > fr.payload_length - 1
            return terminate_connection :PROTOCOL_ERROR
          end
          data = fr.payload[1..-(pad_length+1)]
        end

        @recv_window_size -= fr.payload_length
        Debug.info("Global recv window size = #{@recv_window_size}")
        if @recv_window_size < 128000
          increment = 524288 - @recv_window_size
          @recv_window_size += increment

          if increment > 0
            Debug.info("Sending increment of #{increment / 1024}kb, WS=#{@recv_window_size}")
            bw = H2::BitWriter.new
            bw.write_int32 increment
            send_frame H2::Frame.new(:WINDOW_UPDATE, 0, 4, 0, bw.bytes, false)
          end
        end

        stream.recv_window_size -= fr.payload_length
        Debug.info("Stream #{fr.stream_identifier} recv window size = #{stream.recv_window_size}") if Debug.info?

        if stream.recv_window_size < 128000
          increment = 524288 - stream.recv_window_size
          stream.recv_window_size += increment

          if increment > 0
            Debug.info("Sending increment of #{increment / 1024}kb, WS=#{@recv_window_size} stream=#{fr.stream_identifier}") if Debug.info?
            bw = H2::BitWriter.new
            bw.write_int32 increment
            send_frame H2::Frame.new(:WINDOW_UPDATE, 0, 4, fr.stream_identifier, bw.bytes, false)
          end
        end

        stream.receive_data data.pack('C*'), end_stream
      end

      def handle_h2_headers_frame fr
        flag_end_stream = (fr.flags & 0x01) != 0
        flag_end_headers = (fr.flags & 0x04) != 0
        flag_padded = (fr.flags & 0x08) != 0
        flag_priority = (fr.flags & 0x20) != 0
        hb_index = 0
        hb_index += 1 if flag_padded
        hb_index += 5 if flag_priority

        if Debug.info?
          str_flags = {
            end_stream: flag_end_stream,
            end_headers: flag_end_headers,
            padded: flag_padded,
            priority: flag_priority
          }.select { |k, v| v }.keys.join(',')
          Debug.info("Got headers frame for stream=#{fr.stream_identifier}, flags=#{str_flags}")
        end

        pad_length = 0
        if flag_padded
          pad_length = fr.payload[0]
          if pad_length > (fr.payload_length - hb_index)
            return terminate_connection :PROTOCOL_ERROR
          end
        end

        if flag_priority
          reader = H2::BitReader.new(fr.payload[pad_length...(pad_length+5)])
          return unless parse_priority_frame_payload(reader, fr)
        end

        fragment = fr.payload[hb_index..-(pad_length+1)]

        if fr.stream_identifier <= 0
          return terminate_connection :PROTOCOL_ERROR
        end

        created, stream = get_or_create_stream fr.stream_identifier

        if !stream || !%i(idle).include?(stream.state)
          return terminate_connection :PROTOCOL_ERROR
        end

        # If the whole payload is padding, the fragment could be empty
        return if fragment.empty?

        add_header_block_fragment_to_stream stream, fragment, {
          end_stream: flag_end_stream,
          end_headers: flag_end_headers,
          padded: flag_padded,
          priority: flag_priority,
          _continuation: false
        }
      end

      def handle_h2_continuation_frame fr
        flag_end_headers = (fr.flags & 0x04) != 0
        stream = @h2streams[fr.stream_identifier]

        if !stream || fr.stream_identifier <= 0 || !%i(open idle half_closed_remote).include?(stream.state)
          return terminate_connection :PROTOCOL_ERROR
        end

        add_header_block_fragment_to_stream stream, fr.payload, {
          end_headers: flag_end_headers,
          _continuation: true
        }
      end

      def handle_h2_settings_frame fr
        if fr.payload_length % 6 != 0
          Debug.info "Invalid payload length: #{fr.payload_length}, terminating"
          return terminate_connection :FRAME_SIZE_ERROR
        end

        if fr.stream_identifier != 0
          Debug.info "Got SETTINGS for invalid stream (#{fr.stream_identifier}), terminating"
          return terminate_connection :PROTOCOL_ERROR
        end

        is_ack = ((fr.flags & 1) == 1)
        if is_ack
          Debug.info "Client ACK-ed our SETTINGS frame"

          terminate_connection :FRAME_SIZE_ERROR if fr.payload_length != 0

          return
        end

        new_settings = {}

        Debug.info("Got settings from client")
        num_params = fr.payload_length / 6
        (0...num_params).each do |idx|
          offset = idx * 6
          id = fr.payload[offset...offset+2].pack('C*').unpack('S>')[0]
          value = fr.payload[offset+2...offset+6].pack('C*').unpack('I>')[0]
          new_settings[h2_settingtype_to_sym(id)] = value

          if Debug.info?
            Debug.info("\tSet #{h2_settingtype_to_sym(id)} to #{value}")
          end
        end

        unless [nil, 0, 1].include?(new_settings[:SETTINGS_ENABLE_PUSH])
          Debug.info "Client sent invalid SETTINGS_ENABLE_PUSH (#{new_settings[:SETTINGS_ENABLE_PUSH]}), terminating"
          return terminate_connection :PROTOCOL_ERROR
        end

        if new_settings.has_key?(:SETTINGS_MAX_FRAME_SIZE)
          value = new_settings[:SETTINGS_INITIAL_WINDOW_SIZE]

          unless (16_384..2_147_483_647) === value
            Debug.info "Initial settings window size is out of bounds, terminating"
            return terminate_connection :FLOW_CONTROL_ERROR
          end
        end

        Debug.info("Got some settings, sending ACK") if Debug.info?

        if new_settings.has_key?(:SETTINGS_INITIAL_WINDOW_SIZE)
          new_value = new_settings[:SETTINGS_INITIAL_WINDOW_SIZE]

          if new_value > 2147483647
            Debug.info("Got invalid value for SETTINGS_INITIAL_WINDOW_SIZE (#{new_value}), terminating")
            return terminate_connection :FLOW_CONTROL_ERROR
          end

          if @settings[:SETTINGS_INITIAL_WINDOW_SIZE] != new_settings[:SETTINGS_INITIAL_WINDOW_SIZE]
          # TODO: move this somewhere else

            delta = new_value - @settings[:SETTINGS_INITIAL_WINDOW_SIZE]
            @h2streams.values.each do |stream|
              stream.change_window_size_by delta

              if stream.window_size > 2147483647
                Debug.info("Window size grew too large because initial window size changed, terminating")
                return terminate_connection :FLOW_CONTROL_ERROR
              end
            end
            Debug.info("Initial window size changed by #{delta}")
          end
        end

        new_settings.each do |key, value|
          @settings[key] = value
        end

        ack_frame = H2::Frame.new(:SETTINGS, 1, 0, 0, '', false)
        send_frame ack_frame
      end

      def add_header_block_fragment_to_stream stream, fragment, flags
        result = stream.add_header_block_fragment fragment, flags: flags

        if result == :invalid_state
          terminate_connection :PROTOCOL_ERROR
        elsif result == :hpack_error
          terminate_connection :COMPRESSION_ERROR
        end
      end

      def h2_settingtype_to_sym id
        {
          0x01 => :SETTINGS_HEADER_TABLE_SIZE,
          0x02 => :SETTINGS_ENABLE_PUSH,
          0x03 => :SETTINGS_MAX_CONCURRENT_STREAMS,
          0x04 => :SETTINGS_INITIAL_WINDOW_SIZE,
          0x05 => :SETTINGS_MAX_FRAME_SIZE,
          0x06 => :SETTINGS_MAX_HEADER_LIST_SIZE,
        }[id]
      end
    end
  end
end
