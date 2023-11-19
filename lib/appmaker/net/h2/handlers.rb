# frozen_string_literal: true

module Appmaker::Net::H2
  module Handlers
  end
end

require 'appmaker/net/h2/handlers/priority_frame'
require 'appmaker/net/h2/handlers/ping_frame'
require 'appmaker/net/h2/handlers/rst_frame'
require 'appmaker/net/h2/handlers/continuation_frame'
require 'appmaker/net/h2/handlers/data_frame'
require 'appmaker/net/h2/handlers/goaway_frame'
require 'appmaker/net/h2/handlers/headers_frame'
require 'appmaker/net/h2/handlers/settings_frame'
require 'appmaker/net/h2/handlers/window_update_frame'
