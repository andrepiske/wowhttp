# frozen_string_literal: true
module Appmaker
  module Net
    class RequestBuilder
      FIRSTLINE_REGEX = /\A(GET|POST|PUT|PATCH|HEAD|PRI) (.+) HTTP\/([0-9]\.[0-9])\z/
      HEADERLINE_REGEX = /\A([^:]+): (.+)\z/

      attr_reader :request
      attr_reader :error_reason

      def initialize
        @request = Request.new
        @state = :firstline
      end

      def errored?
        @state == :errored
      end

      def upgrade_to_h2?
        @state == :upgrade_to_h2
      end

      def finished_upgrading_to_h2?
        @state == :finished_h2
      end

      def feed_line line
        return if @state == :errored
        send "_feed_state_#{@state}", line
      end

      private

      def _push_header key, value
        @request.ordered_headers << [key, value]
        @request.headers_hash[key.downcase] = value
      end

      def _feed_state_upgrade_to_h2 line
        line = "\n" if line == ''
        @upgrade_to_h2_content ||= []
        @upgrade_to_h2_content << line

        if @upgrade_to_h2_content.join == "\nSM\n"
          @state = :finished_h2
        end
      end

      def _feed_state_headerline line
        line_match = HEADERLINE_REGEX.match line
        return _mark_errored("headerline doesn't match regex (#{line})") unless line_match
        key = line_match[1]
        value = line_match[2]
        _push_header key, value
      end

      def _feed_state_firstline line
        line_match = FIRSTLINE_REGEX.match line
        return _mark_errored("firstline '#{line}' doesn't match regex (#{line})") unless line_match

        http_major_version, http_minor_version = line_match[3].split('.').map(&:to_i)
        if http_major_version == 1
          if http_minor_version != 1
            _mark_unsupported_protocol(line_match[3])
          end
        elsif http_major_version == 2
          if http_minor_version != 0
            _mark_unsupported_protocol(line_match[3])
          end
        else
          _mark_unsupported_protocol(line_match[3])
        end

        @request.verb = line_match[1].to_sym
        @request.path = CGI.unescape line_match[2]

        if http_major_version == 2
          @state = :upgrade_to_h2
        else
          @state = :headerline
        end
      end

      def _mark_errored reason
        @state = :errored
        @error_reason = reason
        Debug.warn "Warning: RequestBuilder error: #{reason}"
      end

      def _mark_unsupported_protocol protocol_str
        _mark_errored "Protocol '#{protocol_str}' is not supported"
      end
    end
  end
end
