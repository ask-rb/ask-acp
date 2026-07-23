#!/usr/bin/env ruby
# frozen_string_literal: true

# Mock ACP agent for integration testing.
$stdin.sync = true; $stdout.sync = true
require "json"; require "securerandom"

RESPONSES = {
  "initialize" => ->(p) { { protocolVersion: 1, capabilities: {}, serverInfo: { name: "mock-acp-agent", version: "0.1.0" } } },
  "authenticate" => ->(p) { { authenticated: true } },
  "logout" => ->(p) { {} },
  "session/new" => ->(p) { { session: { id: SecureRandom.uuid, status: "running" } } },
  "session/load" => ->(p) { { session: { id: p["sessionId"], status: "running" } } },
  "session/list" => ->(p) { { sessions: [] } },
  "session/resume" => ->(p) { { session: { id: p["sessionId"], status: "running" } } },
  "session/close" => ->(p) { {} },
  "session/cancel" => ->(p) { {} },
  "session/prompt" => ->(p) {
    $stdout.puts(JSON.generate({ jsonrpc: "2.0", method: "text", params: { sessionId: p["sessionId"], content: "Hello from mock ACP agent!" } }))
    $stdout.flush
    { status: "completed" }
  }
}

$stdin.each_line do |line|
  msg = JSON.parse(line) rescue next
  id = msg["id"]; method = msg["method"]; params = msg["params"] || {}
  handler = RESPONSES[method]
  if handler
    begin
      result = handler.call(params)
      $stdout.puts(JSON.generate({ jsonrpc: "2.0", id: id, result: result }))
    rescue => e
      $stdout.puts(JSON.generate({ jsonrpc: "2.0", id: id, error: { code: -32600, message: e.message } }))
    end
  else
    $stdout.puts(JSON.generate({ jsonrpc: "2.0", id: id, error: { code: -32601, message: "Unknown method: #{method}" } }))
  end
  $stdout.flush
end
