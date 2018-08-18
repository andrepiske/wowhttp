# frozen_string_literal: true
module Appmaker::Net
  module Gear
    class ProcGear
      attr_accessor :tap
      attr_accessor :sink

      def initialize sink=nil, &tap
        @tap = tap
        @sink = sink
      end

      # The gear serves as a tap
      def call limit
        notify_writeable limit
      end

      # Called when we can write again
      def notify_writeable limit
        send_proc = proc do |data, finished: false|
          _flush_data data, finished: finished
        end
        @tap.call limit, send_proc
      end

      private

      def _flush_data data, **kw
        @sink.call data, **kw
      end
    end
  end
end
