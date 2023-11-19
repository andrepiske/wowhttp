# frozen_string_literal: true
module Appmaker
  module Net
    module H2::Handlers::WindowUpdateFrame
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
    end
  end
end
