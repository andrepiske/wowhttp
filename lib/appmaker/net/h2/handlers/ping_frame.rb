# frozen_string_literal: true
module Appmaker
  module Net
    module H2::Handlers::PingFrame
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
    end
  end
end
