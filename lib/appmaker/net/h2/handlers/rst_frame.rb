# frozen_string_literal: true
module Appmaker
  module Net
    module H2::Handlers::RstFrame
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
    end
  end
end
