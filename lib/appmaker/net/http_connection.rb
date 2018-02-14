# frozen_string_literal: true
module Appmaker
  module Net
    class HttpConnection < Connection
      def initialize *args
        @request_handler_fabricator = args.pop
        super *args
      end

      def process_request
        start_header_reading
      end

      def on_close
        if @handler
          @handler.closed
          @handler = nil
          @state = :closed
        end
      end

      private

      def start_header_reading
        @state = :initial
        read { |data| _on_read_data data }
      end

      def _onread_read_body data
        # @request_builder.feed_body data
      end

      def _finished_reading_headers
        @handler = _create_request_handler self, @request_builder.request
        @handler.handle_request
      end

      def _create_request_handler *args
        k = @request_handler_fabricator
        if Class === k
          k.new *args
        elsif Proc === k || (k != nil && k.respond_to?(:call))
          k.call *args
        end
      end

      def _onread_closed data
        # do nothing.
      end

      def _onread_initial data
        return if data == nil

        if @line_reader == nil
          @request_builder = RequestBuilder.new
          @line_reader = Appmaker::Net::LineStreamingBuffer.new do |line|
            line = (line.chars - ["\r"]).join
            if line == ''
              _finished_reading_headers
              @line_reader.finish
              remaining_buffer = @line_reader.buffer.join
              @line_reader = nil
              @state = :read_body
              _on_read_data remaining_buffer if remaining_buffer.length > 0
            else
              @request_builder.feed_line line
            end
          end
        end
        @line_reader.feed data
      end

      def _on_read_data data
        send("_onread_#{@state}", data)
      end
    end
  end
end
