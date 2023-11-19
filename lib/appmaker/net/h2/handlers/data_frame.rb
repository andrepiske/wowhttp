# frozen_string_literal: true
module Appmaker
  module Net
    module H2::Handlers::DataFrame
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
    end
  end
end
