# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# Integration tests that spawn a real Ruby ACP agent as a subprocess.
class ACPIntegrationTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("acp_test")
    # Create a mock ACP agent script
    @agent_script = File.join(@tmpdir, "mock_agent.rb")
    File.write(@agent_script, MOCK_AGENT_SCRIPT)
    File.chmod(0o755, @agent_script)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_initialize_handshake
    client = Ask::ACP::Client.new(command: ["ruby", @agent_script], request_timeout: 5)
    client.start
    result = client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    assert result.is_a?(Hash), "Initialize should return a Hash"
    assert result["serverInfo"] || result[:serverInfo], "Should have serverInfo"
    client.stop
  end

  def test_session_new
    client = Ask::ACP::Client.new(command: ["ruby", @agent_script], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    session = client.session_new(cwd: @tmpdir)
    assert session[:id], "Should return a session id"
    assert session[:status], "Should return a status"
    client.stop
  end

  def test_full_prompt_flow
    client = Ask::ACP::Client.new(command: ["ruby", @agent_script], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    session = client.session_new(cwd: @tmpdir)
    assert session[:id], "Session should be created"

    result = client.request("session/prompt", { sessionId: session[:id], input: "Say hello" })
    assert result, "Prompt should return a result"
    client.stop
  end

  def test_session_list
    client = Ask::ACP::Client.new(command: ["ruby", @agent_script], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    sessions = client.session_list
    assert_kind_of Array, sessions
    client.stop
  end

  def test_session_close
    client = Ask::ACP::Client.new(command: ["ruby", @agent_script], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    session = client.session_new(cwd: @tmpdir)
    result = client.session_close(session[:id])
    assert result.is_a?(Hash), "Close should return a result"
    client.stop
  end

  def test_error_on_unknown_method
    client = Ask::ACP::Client.new(command: ["ruby", @agent_script], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    assert_raises(Ask::ACP::Error) do
      client.request("nonexistent/method", {})
    end
    client.stop
  end

  def test_logout
    client = Ask::ACP::Client.new(command: ["ruby", @agent_script], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    result = client.request("logout", {})
    assert result.is_a?(Hash)
    client.stop
  end

  # A minimal Ruby ACP agent for testing
  MOCK_AGENT_SCRIPT = <<~'RUBY'
    #!/usr/bin/env ruby
    # frozen_string_literal: true

    $stdin.sync = true
    $stdout.sync = true

    require "json"
    require "securerandom"

    RESPONSES = {
      "initialize" => ->(params) {
        { protocolVersion: 1, capabilities: {},
          serverInfo: { name: "mock-acp-agent", version: "0.1.0" } }
      },
      "authenticate" => ->(params) {
        { authenticated: true }
      },
      "logout" => ->(params) {
        {}
      },
      "session/new" => ->(params) {
        { session: { id: SecureRandom.uuid, status: "running" } }
      },
      "session/load" => ->(params) {
        { session: { id: params["sessionId"], status: "running" } }
      },
      "session/list" => ->(params) {
        { sessions: [] }
      },
      "session/resume" => ->(params) {
        { session: { id: params["sessionId"], status: "running" } }
      },
      "session/close" => ->(params) {
        {}
      },
      "session/prompt" => ->(params) {
        $stdout.puts(JSON.generate({ jsonrpc: "2.0", method: "text",
          params: { sessionId: params["sessionId"], content: "Hello from mock ACP agent!" } }))
        $stdout.flush
        { status: "completed" }
      },
      "session/cancel" => ->(params) {
        {}
      }
    }

    $stdin.each_line do |line|
      msg = JSON.parse(line) rescue next
      id = msg["id"]
      method = msg["method"]
      params = msg["params"] || {}

      handler = RESPONSES[method]
      if handler
        begin
          result = handler.call(params)
          response = { jsonrpc: "2.0", id: id, result: result }
          $stdout.puts(JSON.generate(response))
          $stdout.flush
        rescue => e
          response = { jsonrpc: "2.0", id: id, error: { code: -32600, message: e.message } }
          $stdout.puts(JSON.generate(response))
          $stdout.flush
        end
      else
        response = { jsonrpc: "2.0", id: id, error: { code: -32601, message: "Unknown method: #{method}" } }
        $stdout.puts(JSON.generate(response))
        $stdout.flush
      end
    end
  RUBY
end
