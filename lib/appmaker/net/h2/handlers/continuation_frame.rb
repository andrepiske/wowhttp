# frozen_string_literal: true
module Appmaker
  module Net
    module H2::Handlers::ContinuationFrame
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
    end
  end
end
