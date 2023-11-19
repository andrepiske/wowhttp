# frozen_string_literal: true
module Appmaker
  module Net
    module H2::Handlers::GoawayFrame
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
    end
  end
end
