# frozen_string_literal: true
module Appmaker
  module Net
    module H2::Handlers::HeadersFrame
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
    end
  end
end
