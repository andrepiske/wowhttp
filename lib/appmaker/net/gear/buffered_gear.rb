# frozen_string_literal: true
module Appmaker::Net
  module Gear
    class BufferedGear
      attr_accessor :sink

      def initialize sink=nil
        @sink = sink
      end

    end
  end
end
