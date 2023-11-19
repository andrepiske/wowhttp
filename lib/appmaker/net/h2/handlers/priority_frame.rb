# frozen_string_literal: true
module Appmaker
  module Net
    module H2::Handlers::PriorityFrame
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
    end
  end
end
