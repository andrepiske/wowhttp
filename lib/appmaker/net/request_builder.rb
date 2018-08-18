# frozen_string_literal: true
module Appmaker
  module Net
    class RequestBuilder
      FIRSTLINE_REGEX = /\A(GET|POST|PUT|PATCH|HEAD) (.+) (HTTP\/1\.[01])\z/
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

      def feed_line line
        return if @state == :errored
        send "_feed_state_#{@state}", line
      end

      private

      def _push_header key, value
        @request.ordered_headers << [key, value]
        @request.headers_hash[key.downcase] = value
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
        return _mark_errored("firstline doesn't match regex (#{line})") unless line_match
        @request.verb = line_match[1].to_sym
        @request.path = CGI.unescape line_match[2]
        @state = :headerline
      end

      def _mark_errored reason
        @state = :errored
        @error_reason = reason
      end
    end
  end
end
