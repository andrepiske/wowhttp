# frozen_string_literal: true
module Appmaker
  module Debug
    class << self
      def enabled?
        false
        # true
      end

      def info?; enabled?; end
      def warn?; enabled?; end
      def errork?; enabled?; end

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
