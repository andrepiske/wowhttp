# frozen_string_literal: true
module Appmaker
  module Net
    class Http2Stream
      attr_accessor :sid
      attr_accessor :state
      attr_accessor :connection # the "real" connection behind this

      def initialize(sid, connection, request_handler_fabricator)
        @state = :idle
        @sid = sid
        @connection = connection
        @request_handler_fabricator = request_handler_fabricator
      end

      def receive_headers headers, flags:
        raise 'Invalid state' unless @state == :idle
        @headers = headers
        @state = :open
        puts("Stream #{sid} went from :idle to :open")

        if flags[:end_stream]
          puts("Stream #{sid} went from #{state} to :half_closed_remote because it had end_stream flag")
          @state = :half_closed_remote
          _process_request
        end
      end

      # Stub method to tell request handler that we don't recycle connections
      def recycle
        false
      end

      def make_frame type, bit_writer
        connection.make_frame type, bit_writer, sid: @sid
      end

      def send_header_and_finish response, &block
        send_header response, end_stream: true, &block
      end

      def write_then_finish content, &block
        max_bytes = connection.settings[:SETTINGS_MAX_FRAME_SIZE]
        cursor = 0

        loop do
          chunk = content[cursor...(cursor + max_bytes)]
          is_last = ((cursor + max_bytes) > content.length)

          writer = H2::BitWriter.new
          writer.write_bytes chunk
          frame = make_frame :DATA, writer
          if is_last
            frame.flags = 0x01 # END_STREAM
            connection.send_frame frame, &block
          else
            connection.send_frame frame
          end

          cursor += max_bytes
          break if is_last
        end
      end

      def finish
        if @state != :closed
          @state = :closed
          connection.close_stream @sid
        end
      end

      def on_close
        @state = :closed
        connection.mark_stream_closed @sid
      end

      def send_header response, end_stream: false, &block
        writer = H2::BitWriter.new
        # writer.write_byte 0 # pad length
        # writer.write_int32 0
        # writer.write_byte 0

        header_encoder = H2::HpackEncoder.new writer, @hpack_local_context
        header_encoder.dump response

        # $foo = 'qux'
        # ctx = H2::HpackContext.new
        # decoder = H2::HpackDecoder.new(writer.bytes, ctx)
        # decoder.decode_all

        frame = make_frame :HEADERS, writer
        frame.flags = 0x04
        frame.flags ||= 0x01 if end_stream
        connection.send_frame frame, &block
      end

      # def write data
      #   connection.stream_write sid, data
      # end

      private

      def _process_request
        request = Request.new
        @headers.each do |name, value|
          if name[0] == ':'
            request.path = value if name == ':path'
            request.verb = value if name == ':method'
          else
            request.headers.add_header name, value
          end
        end
        puts("Handling H2 request now")
        @handler = _create_request_handler self, request
        @handler.handle_request
        # run the request and answer the client
      end

      # FIXME: Duplicated method in HttpConnection class
      def _create_request_handler *args
        k = @request_handler_fabricator
        if Class === k
          k.new *args
        elsif Proc === k || (k != nil && k.respond_to?(:call))
          k.call *args
        end
      end

    end
  end
end
