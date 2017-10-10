# frozen_string_literal: true
if ENV['debug'] == 'true'
  require 'pry'
  require 'pry-byebug'
end

require 'appmaker'

module Appmaker
  class CLI
    def self.bootstrap
      file_name = File.expand_path ARGV[0]
      ::Kernel.load file_name, true
    end
  end
end
