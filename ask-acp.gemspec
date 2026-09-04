# frozen_string_literal: true

require_relative "lib/ask/acp/version"

Gem::Specification.new do |spec|
  spec.name = "ask-acp"
  spec.version = Ask::ACP::VERSION
  spec.authors = ["Kaka Ruto"]
  spec.email = ["kaka@myrrlabs.com"]

  spec.summary = "Agent Client Protocol for Ruby"
  spec.description = "Ruby implementation of the Agent Client Protocol (ACP) — a JSON-RPC standard for agent-editor communication. Includes client (connect to ACP agents), server (host Ruby agents via ACP), and transport layer."

  spec.homepage = "https://github.com/ask-rb/ask-acp"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*", "exe/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["record_acp"]
  spec.require_paths = ["lib"]

  spec.add_dependency "json"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "mocha", "~> 3.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
