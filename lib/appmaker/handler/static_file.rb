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

        # puts("Will serve file #{file_path}")
        content = File.read(file_path).force_encoding('ASCII-8BIT')

        response.set_header 'Accept-Ranges', 'bytes'

        types = {
          '.html' => 'text/html',
          '.mp4' => 'video/mp4',
          '.jpg' => 'image/jpeg',
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

        response.set_header 'Content-Length', content.length

        header = response.full_header
        # puts("Answering with #{content.length} bytes with header #{header}")

        @http_connection.write header
        @http_connection.write content do
          # puts('Finished!')
          @http_connection.finish
        end

        true
      end

    end
  end
end
