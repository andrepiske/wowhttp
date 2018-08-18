module Appmaker
  module Net
    module H2
      Frame = Struct.new(:type, :flags, :payload_length, :stream_identifier, :payload)
    end
  end
end
