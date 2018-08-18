# frozen_string_literal: true
module Appmaker
  module Handler
    class StaticFile < Base
      def handle_request
        file_path = File.expand_path File.join('public', @request.path[1..-1])

        # puts("Want file #{file_path} (#{@request.verb} #{@request.path})")
        # puts("Headers: #{@request.ordered_headers}")
        return false unless File.file? file_path

        response = make_base_response
        file_mtime = File.mtime(file_path).to_datetime

        if @request.headers_hash['if-modified-since']
          if_modified_since = DateTime.parse(@request.headers_hash['if-modified-since'])
          if file_mtime <= if_modified_since
            response.code = 304
            @http_connection.send_header_and_finish response
            return true
          end
        end

        # puts("Will serve file #{file_path}")
        content = File.read(file_path).force_encoding('ASCII-8BIT')

        response.set_header 'Accept-Ranges', 'bytes'

        types = {
          '.html' => 'text/html',
          '.mp4' => 'video/mp4',
          '.jpg' => 'image/jpeg',
          '.js' => 'text/javascript',
        }
        mime_type = types.fetch File.extname(file_path), 'application/octet-stream'

        range = @request.headers_hash['range']
        # range = nil
        if range != nil
          type, range_data = range.split('=')
          start_offset, end_offset = range_data.split('-')
          start_offset = 0 unless start_offset =~ /\A[0-9]+\z/
          end_offset = (content.length - 1) unless end_offset =~ /\A[0-9]+\z/

          start_offset = start_offset.to_i
          end_offset = end_offset.to_i

          start_offset = [0, [start_offset, content.length - 1].min].max
          end_offset = [0, [end_offset, content.length - 1].min].max
          if start_offset > end_offset
            start_offset, end_offset = end_offset, start_offset
          end

          full_length = content.length
          content = content.slice(start_offset..end_offset)

          response.code = 206
          response.set_header 'Content-Range', "bytes #{start_offset}-#{end_offset}/#{full_length}"
        end

        # response.set_header 'Cache-Control', 'public, max-age=20'
        response.set_header 'Last-Modified', file_mtime.rfc2822

        response.set_header 'Content-Length', content.length
        # response.set_header 'Transfer-Encoding', 'chunked'
        #
        # response.set_header 'Cache-Control', 'public'
        #
        # size_hex = content.length.to_s(16)
        # answer_content = "#{size_hex}\r\n#{content}\r\n0\r\n\r\n".encode('ASCII-8BIT')
        #
        # pc = content.bytes.map { |c| "1\r\n#{c.chr}\r\n" }.join('')
        # answer_content = "#{pc}0\r\n\r\n".encode('ASCII-8BIT')

        # binding.pry
        @http_connection.send_header response
        @http_connection.write_then_finish content

        true
      end

    end
  end
end
