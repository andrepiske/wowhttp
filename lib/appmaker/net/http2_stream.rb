# frozen_string_literal: true
module Appmaker
  module Net
    # From RFC 7540, page 24:
    #
    #    The lifecycle of a stream is shown in Figure 2.
    #
    #                                +--------+
    #                        send PP |        | recv PP
    #                       ,--------|  idle  |--------.
    #                      /         |        |         \
    #                     v          +--------+          v
    #              +----------+          |           +----------+
    #              |          |          | send H /  |          |
    #       ,------| reserved |          | recv H    | reserved |------.
    #       |      | (local)  |          |           | (remote) |      |
    #       |      +----------+          v           +----------+      |
    #       |          |             +--------+             |          |
    #       |          |     recv ES |        | send ES     |          |
    #       |   send H |     ,-------|  open  |-------.     | recv H   |
    #       |          |    /        |        |        \    |          |
    #       |          v   v         +--------+         v   v          |
    #       |      +----------+          |           +----------+      |
    #       |      |   half   |          |           |   half   |      |
    #       |      |  closed  |          | send R /  |  closed  |      |
    #       |      | (remote) |          | recv R    | (local)  |      |
    #       |      +----------+          |           +----------+      |
    #       |           |                |                 |           |
    #       |           | send ES /      |       recv ES / |           |
    #       |           | send R /       v        send R / |           |
    #       |           | recv R     +--------+   recv R   |           |
    #       | send R /  `----------->|        |<-----------'  send R / |
    #       | recv R                 | closed |               recv R   |
    #       `----------------------->|        |<----------------------'
    #                                +--------+
    #
    #          send:   endpoint sends this frame
    #          recv:   endpoint receives this frame
    #
    #          H:  HEADERS frame (with implied CONTINUATIONs)
    #          PP: PUSH_PROMISE frame (with implied CONTINUATIONs)
    #          ES: END_STREAM flag
    #          R:  RST_STREAM frame
    #
    #                          Figure 2: Stream States
    #
    class Http2Stream
      attr_accessor :sid
      attr_reader :state
      attr_accessor :connection # the Http2Connection behind this
      attr_accessor :window_size # flow-control window size
      attr_reader :gear

      def initialize(sid, connection, request_handler_fabricator)
        @state = :idle
        @sid = sid
        @connection = connection
        @request_handler_fabricator = request_handler_fabricator
        @window_size = 65535
      end

      def dump_diagnosis_info
        puts(" H2 stream sid=#{@sid} in state=#{@state}")
        puts(" Window size=#{@window_size}")
        puts(" Handler class = #{@handler.class}")
        if @_debug_request
          puts(" Request dump:")
          @_debug_request.dump_diagnosis_info
        else
          puts(" Request is nil")
        end
      end

      def receive_headers headers, flags:
        raise 'Invalid state' unless @state == :idle
        @headers = headers
        @state = :open
        @finished = false

        set_state_to :open

        if flags[:end_stream]
          set_state_to :half_closed_remote
          _process_request
        end
      end

      def set_state_to new_state
        puts("Stream #{sid} went from #{state} to #{new_state}")
        @state = new_state
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

      def change_window_size_by delta
        @window_size += delta
      end

      # How many bytes are we allowed to send based
      # on flow-control protocol
      def sending_limit
        max_frame_size = connection.settings[:SETTINGS_MAX_FRAME_SIZE]
        [@window_size, connection.window_size, max_frame_size].min
      end

      # We are blocked from sending data right now
      def blocked_from_sending?
        @state == :half_closed_remote && sending_limit == 0
      end

      # Whether we are intending to send more data
      def intents_to_write?
        @gear != nil && !@finished && !blocked_from_sending?
      end

      # We can write again, so let's make the gear turn!
      def turn_gear
        limit = sending_limit
        return if @gear == nil || limit == 0
        @gear.notify_writeable limit
      end

      def geared_send &tap
        sink = proc do |data, finished: false|
          is_finished = finished
          if data != nil
            @window_size -= data.length
            connection.change_window_size_by(-data.length)
            # puts("Sending geared #{data.length} bytes")
            send_data_frame data, end_stream: finished do
              mark_finished if finished
            end
          end
        end
        @gear = Net::Gear::ProcGear.new sink, &tap
        connection.register_gear @gear
        @gear
      end

      def send_data_frame data, end_stream: false, &block
        writer = H2::BitWriter.new
        writer.write_bytes data
        frame = make_frame :DATA, writer
        frame.flags = 0x01 if end_stream
        connection.send_frame frame, &block
      end

      # TODO: replace by BufferedGear
      def write_then_finish content, &block
        max_bytes = connection.settings[:SETTINGS_MAX_FRAME_SIZE]
        cursor = 0

        loop do
          chunk = content[cursor...(cursor + max_bytes)]
          is_last = ((cursor + max_bytes) > content.length)

          send_data_frame chunk, end_stream: is_last do
            mark_finished if is_last
          end

          cursor += max_bytes
          break if is_last
        end
      end

      def mark_finished
        return if @finished
        @finished = true
        set_state_to :closed unless @state == :closed
        connection.mark_stream_closed @sid
      end

      def finish
        mark_finished
        connection.send_rst_stream @sid
      end

      def finished?
        @finished
      end

      def on_rst_stream
        mark_finished
        # TODO: notify gear that stream has been closed, so it has a chance to free up resources
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

      def write data, &block
        raise "Cannot write to geared stream!" if @gear
        send_data_frame data, &block
      end

      private

      def _process_request
        request = Request.new
        @_debug_request = request
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
