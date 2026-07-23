# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "test/"
  add_filter "version.rb"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ask-acp"
require "minitest/autorun"
require "mocha/minitest"
require "json"
require "stringio"
