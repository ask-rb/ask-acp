# frozen_string_literal: true

require_relative "acp/version"
require_relative "acp/protocol"
require_relative "acp/client"
require_relative "acp/server"

module Ask
  module ACP
    class Error < StandardError; end
    class TimeoutError < Error; end
  end
end
