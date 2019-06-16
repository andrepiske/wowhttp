# frozen_string_literal: true
if ENV['debug'] == 'true'
  require 'pry'
  require 'pry-byebug' unless RUBY_PLATFORM =~ /java/
end

require 'appmaker'

module Appmaker
  class CLI
    def self.bootstrap
      if ARGV[0] == nil
        puts("Usage: appmaker <file.rb>")
        exit 1
      end
      Process.setproctitle('appmaker')

      file_name = File.expand_path ARGV[0]
      ::Kernel.load file_name, true
    end
  end
end
