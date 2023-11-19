# frozen_string_literal: true
module Appmaker
  # Is debug mode enabled?
  def self.debug?
    ::Appmaker::Debug.enabled?
  end

  # Is monitoring enabled?
  def self.mon?
    $appmaker_mon[:enabled]
  end
end

if ENV['APPMAKER_MON'] == '1'
  $appmaker_mon = { enabled: true, metrics: {
    readables: 0,
    writables: 0,
    new_clients: 0,
    clients: 0,

    streams: 0,
    closed_streams: 0,
    write_buffer_length: 0,
    write_buffer_chunks: 0,
  } }
else
  $appmaker_mon = { enabled: false }
end

require 'cgi'
require 'forwardable'
require 'openssl'
require 'set'

require 'appmaker/debug'
require 'appmaker/request'
require 'appmaker/net'
require 'appmaker/semantic'
require 'appmaker/response'
require 'appmaker/handler'
