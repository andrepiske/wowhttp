# frozen_string_literal: true
module Appmaker
  module Net
    class HttpConnection < Connection
      attr_accessor :recycle

      def initialize *args
        @request_handler_fabricator = args.pop
        super *args
      end

      def dump_diagnosis_info
        Debug.error("HTTP/1.1 connection in state=#{@state}")
        Debug.error("Has gear? #{@gear == nil ? 'no' : 'yes'}")
        Debug.error("Handler class = #{@handler.class}")
        if @_debug_request
          Debug.error("Request dump:")
          @_debug_request.dump_diagnosis_info
        else
          Debug.error("Request is nil")
        end
      end

      def go!
        start_header_reading
      end

      def finish
        if recycle
          @gear = nil
          recycle_connection
        else
          close
        end
      end

      def set_keepalive value
        @recycle = value
      end

      def set_async!
        # no-op
      end

      def on_close
        h = @handler
        if h
          @handler = nil
          h.closed
          @state = :closed
        end
      end

      def on_writeable
        return if @gear == nil
        @gear.notify_writeable(16 * 1024)
      end

      def has_write_intention?
        super || @gear != nil
      end

      def geared_send &tap
        sink = proc do |data, finished:|
          if data
            write data
          end
          finish if finished
        end
        @gear = Gear::ProcGear.new sink, &tap
        _register_write_intention
      end

      def write_then_finish data
        write data do
          finish
        end
      end

      def send_header response, &block
        phrase = Response::CODE_TO_REASON_PHRASE_MAPPING.fetch response.code, 'Whatever'
        firstline = "HTTP/1.1 #{response.code} #{phrase}"
        headers = response.headers.ordered_headers.map do |k, v|
          "#{k}: #{v}"
        end.join("\r\n")

        write "#{firstline}\r\n#{headers}\r\n\r\n", &block
      end

      private

      def recycle_connection
        h = @handler
        if h
          @handler = nil
          h.closed
        end
      end

      def start_header_reading
        @state = :initial
        read { |data| _on_read_data data }
      end

      def _onread_read_body data
        # @request_builder.feed_body data
      end

      def _finished_reading_headers
        if @request_builder.errored?
          raise "RequestBuilder errored! Reason = #{@request_builder.error_reason}"
        end

        if @request_builder.upgrade_to_h2?
          binding.pry
        end

        request = @request_builder.request
        request.protocol = 'http/1.1'
        @_debug_request = request # for debugging only
        @handler = _create_request_handler self, request
        @recycle = request.safe? # FIXME: should we use idempotent or safe here?
        head = request.ordered_headers.map { |k, v| "\n\t\t#{k}: #{v}" }.join('')

        Debug.info("\nHandle a #{request.verb} #{request.path} with:#{head}") if Debug.info?
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

      def _onread_recycling data
        @state = :initial
        _onread_initial data
      end

      def _process_read_line line
        if line == '' && @request_builder.upgrade_to_h2?
          @request_builder.feed_line line
          if @request_builder.finished_upgrading_to_h2?
            @server.upgrade_connection_to_h2 self
          end
        elsif line == ''
          _finished_reading_headers
          @line_reader.finish
          remaining_buffer = @line_reader.buffer.join
          @line_reader = nil
          return if @closed

          # Handler finished processing, we now might either recycle or close the connection
          if @handler == nil
            if @request_builder.request.has_body?
              # Someone wants to ignore the content and just finish the request
              # We won't handle this case as it is kinda non-sense. Let's just close the connection instead
              close
            else
              @state = :recycling
            end
          else
            if @request_builder.request.has_body?
              @state = :read_body
              _on_read_data remaining_buffer if remaining_buffer.length > 0
            end
          end
        else
          @request_builder.feed_line line
        end
      end

      def _onread_initial data
        return if data == nil

        if @line_reader == nil
          @request_builder = RequestBuilder.new
          @line_reader = Appmaker::Net::LineStreamingBuffer.new do |line|
            _process_read_line((line.chars - ["\r"]).join)
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
