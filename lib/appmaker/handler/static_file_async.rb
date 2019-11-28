# frozen_string_literal: true
require 'marcel'
require 'fcntl'

module Appmaker
  module Handler
    class StaticFileAsync < Base
      def initialize options, *args
        super *args
        @base_path = options[:base_path]
        @buffer_size = options.fetch(:buffer_size, 16 * 1024)
      end

      def handle_request
        file_path = File.expand_path File.join(@base_path, @request.path[1..-1])

        if Debug.info?
          Debug.info("Want async file #{file_path} (#{@request.verb} #{@request.path})")
          Debug.info("Headers: #{@request.ordered_headers}")
        end

        file_stat = nil
        begin
          file_stat = File.stat(file_path)
        rescue Errno::ENOENT
          return false
        end

        response = make_base_response
        file_mtime = file_stat.mtime.to_datetime
        file_size = file_stat.size

        if @request.headers_hash['if-modified-since']
          if_modified_since = DateTime.parse(@request.headers_hash['if-modified-since'])

          if file_mtime <= if_modified_since
            response.code = 304
            @http_connection.send_header_and_finish response
            return true
          end
        end

        Debug.info("Will serve file #{file_path} asynchronously")

        response.set_header 'Accept-Ranges', 'bytes'

        mime_type = Marcel::MimeType.for extension: File.extname(file_path)
        response.set_header 'Content-Type', mime_type

        range = @request.headers_hash['range']
        if range != nil
          type, range_data = range.split('=')
          start_offset, end_offset = range_data.split('-')
          start_offset = 0 unless start_offset =~ /\A[0-9]+\z/
          end_offset = (file_size - 1) unless end_offset =~ /\A[0-9]+\z/

          start_offset = start_offset.to_i
          end_offset = end_offset.to_i

          start_offset = [0, [start_offset, file_size - 1].min].max
          end_offset = [0, [end_offset, file_size - 1].min].max
          if start_offset > end_offset
            start_offset, end_offset = end_offset, start_offset
          end

          sending_range = (start_offset..end_offset)

          response.code = 206
          response.set_header 'Content-Length', sending_range.size
          response.set_header 'Content-Range', "bytes #{start_offset}-#{end_offset}/#{file_size}"
          return serve_file_contents response, file_path, sending_range
        end

        response.set_header 'Last-Modified', file_mtime.rfc2822
        response.set_header 'Content-Length', file_size

        return serve_file_contents response, file_path, (0...file_size)
      end

      private

      def serve_file_contents response, file_path, range
        file = File.open(file_path, mode: 'rb', encoding: Encoding::ASCII_8BIT, flags: Fcntl::O_NONBLOCK)
        file.seek range.min
        amount_to_send = range.size

        # @http_connection.hint! send_buffer_size: @buffer_size
        @http_connection.send_header response

        buffered_gear = Net::Gear::BufferedGear.new(@buffer_size) do |limit, send_proc|
          limit = [amount_to_send, limit].min
          begin
            if file.closed?
              Debug.info("Attempt to send file, but it's already closed sid=#{@http_connection&.sid}")
              next
            end
            Debug.info("Async File: read #{limit} bytes")
            content = file.read_nonblock limit

            amount_to_send -= content.length
            file.close if amount_to_send <= 0

            send_proc.call content, finished: (amount_to_send <= 0)
          rescue IO::WaitReadable
          end
        end

        @http_connection.geared_send &buffered_gear.tap

        true
      end
    end
  end
end
