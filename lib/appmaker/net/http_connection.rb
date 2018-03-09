# frozen_string_literal: true
module Appmaker
  module Net
    class HttpConnection < Connection
      attr_accessor :recycle

      def initialize *args
        @request_handler_fabricator = args.pop
        super *args
      end

      def process_request
        start_header_reading
      end

      def finish
        if recycle
          recycle_connection
        else
          close
        end
      end

      def on_close
        if @handler
          @handler.closed
          @handler = nil
          @state = :closed
        end
      end

      def write_then_finish data
        write data do
          finish
        end
      end

      private

      def recycle_connection
        @lock.synchronize do
          @handler.closed
          @handler = nil
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
        request = @request_builder.request
        @handler = _create_request_handler self, request
        @recycle = request.idempotent?
        head = request.ordered_headers.map { |k, v| "\n\t\t#{k}: #{v}" }.join('')
        puts("\nHandle a #{request.verb} #{request.path} with:#{head}")
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

      # def _check_http2 data
      #   return false if @http_version != :http2
      #   # might have broken frames
      #   return false unless data.length >= 24 && data[0...24].bytes == expected_preface
      #   puts('Using http2!')
      #   binding.pry
      # end

      def _handle_h2_frame fr
        if fr.type == :SETTINGS
          _handle_h2_settings_frame fr
        elsif fr.type == :HEADERS
          _handle_h2_header_frame fr
        else
          puts("frame of type #{fr.type}")
        end
      end

      def _handle_h2_header_frame fr
        flag_end_stream = (fr.flags & 0x01) != 0
        flag_end_headers = (fr.flags & 0x04) != 0
        flag_padded = (fr.flags & 0x08) != 0
        flag_priority = (fr.flags & 0x20) != 0
        hb_index = 0
        hb_index += 1 if flag_padded
        hb_index += 5 if flag_priority

        header_data = fr.payload[hb_index..-1]
        decoder = H2::HpackDecoder.new(header_data)
        headers = decoder.decode_all

        str_flags = {
          'end_stream' => flag_end_stream,
          'end_headers' => flag_end_headers,
          'padded' => flag_padded,
          'priority' => flag_priority
        }.select { |k, v| v }.map { |k, v| k }.join(',')
        puts("Reader headers: #{headers} with flags=#{str_flags}")
      end

      def _h2_settingtype_to_sym id
        {
          0x01 => :SETTINGS_HEADER_TABLE_SIZE,
          0x02 => :SETTINGS_ENABLE_PUSH,
          0x03 => :SETTINGS_MAX_CONCURRENT_STREAMS,
          0x04 => :SETTINGS_INITIAL_WINDOW_SIZE,
          0x05 => :SETTINGS_MAX_FRAME_SIZE,
          0x06 => :SETTINGS_MAX_HEADER_LIST_SIZE,
        }[id]
      end

      def _handle_h2_settings_frame fr
        is_ack = ((fr.flags & 1) == 1)
        if is_ack
          puts "ACKing the settings ;)"
          return
        end

        @h2_settings ||= {}

        num_params = fr.payload_length / 6
        (0...num_params).each do |idx|
          offset = idx * 6
          id = fr.payload[offset...offset+2].pack('C*').unpack1('S>')
          value = fr.payload[offset+2...offset+6].pack('C*').unpack1('I>')
          @h2_settings[_h2_settingtype_to_sym(id)] = value
        end
        puts("got some settings over here!")
        # binding.pry
      end

      def _onread_initial data
        return if data == nil

        if @http_version == :http2
          if @frame_reader == nil
            @frame_reader = Appmaker::Net::Http2StreamingBuffer.new do |hframe|
              _handle_h2_frame hframe
            end
          end
          @frame_reader.feed data
          return
        end

        if @line_reader == nil
          @request_builder = RequestBuilder.new
          @line_reader = Appmaker::Net::LineStreamingBuffer.new do |line|
            line = (line.chars - ["\r"]).join
            if line == ''
              _finished_reading_headers
              @line_reader.finish
              remaining_buffer = @line_reader.buffer.join
              @line_reader = nil
              next if @closed

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
        end
        @line_reader.feed data
      end

      def _on_read_data data
        send("_onread_#{@state}", data)
      end
    end
  end
end
