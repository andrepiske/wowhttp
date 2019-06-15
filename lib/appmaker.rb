# frozen_string_literal: true
module Appmaker
  def self.debug?
    ::Appmaker::Debug.enabled?
  end
end

require 'cgi'
require 'forwardable'
require 'openssl'

require 'appmaker/debug'
require 'appmaker/request'
require 'appmaker/net'
require 'appmaker/semantic'
require 'appmaker/response'
require 'appmaker/handler'
