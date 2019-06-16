# frozen_string_literal: true
module Appmaker
  module Debug
    class << self
      def debug_level
        return 0 if @no_debug
        if ENV['APPMAKER_DEBUG'] == nil
          @no_debug = true
          return 0
        end

        case ENV['APPMAKER_DEBUG']&.downcase
        when 'debug', 'info', 'true'
          3
        when 'warn'
          2
        when 'error'
          1
        else
          0
        end
      end

      def enabled?
        debug_level >= 3
      end

      def info?; debug_level >= 3; end
      def warn?; debug_level >= 2; end
      def error?; debug_level >= 1; end

      def info(*args)
        return unless info?
        puts(*args)
      end

      def warn(*args)
        return unless warn?
        puts(*args)
      end

      def error(*args)
        return unless error?
        puts(*args)
      end
    end
  end
end
