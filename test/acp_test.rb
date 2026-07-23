# frozen_string_literal: true

require_relative "test_helper"

class ACPTest < Minitest::Test
  # ── Protocol tests ──

  def test_build_request_includes_jsonrpc
    msg = Ask::ACP::Protocol.build_request("session/new", { cwd: "/tmp" }, id: 1)
    assert_equal "2.0", msg[:jsonrpc]
    assert_equal 1, msg[:id]
    assert_equal "session/new", msg[:method]
    assert_equal "/tmp", msg[:params][:cwd]
  end

  def test_build_request_without_id
    msg = Ask::ACP::Protocol.build_request("session/new", { cwd: "/tmp" })
    assert_equal "2.0", msg[:jsonrpc]
    assert_nil msg[:id]
    assert_equal "session/new", msg[:method]
  end

  def test_build_request_without_params
    msg = Ask::ACP::Protocol.build_request("session/list")
    assert_equal "session/list", msg[:method]
    refute msg.key?(:params)
  end

  def test_build_response
    msg = Ask::ACP::Protocol.build_response(1, { id: "sess_1" })
    assert_equal "2.0", msg[:jsonrpc]
    assert_equal 1, msg[:id]
    assert_equal "sess_1", msg[:result][:id]
  end

  def test_build_error
    msg = Ask::ACP::Protocol.build_error(1, -32_600, "Bad request")
    assert_equal "2.0", msg[:jsonrpc]
    assert_equal -32_600, msg[:error][:code]
    assert_equal "Bad request", msg[:error][:message]
  end

  def test_parse_valid_json
    result = Ask::ACP::Protocol.parse('{"jsonrpc":"2.0","method":"test"}')
    assert_equal "test", result["method"]
  end

  def test_parse_invalid_json
    assert_nil Ask::ACP::Protocol.parse("not json")
  end

  def test_parse_empty_line
    assert_nil Ask::ACP::Protocol.parse("")
    assert_nil Ask::ACP::Protocol.parse(nil)
  end

  def test_serialize_adds_newline
    json = Ask::ACP::Protocol.serialize({ test: 1 })
    assert_equal "{\"test\":1}\n", json
  end

  def test_protocol_constants
    assert_equal "session/new", Ask::ACP::Protocol::AGENT_METHODS[:session_new]
    assert_equal "session/prompt", Ask::ACP::Protocol::AGENT_METHODS[:session_prompt]
    assert_equal "session/list", Ask::ACP::Protocol::AGENT_METHODS[:session_list]
    assert_equal "session/load", Ask::ACP::Protocol::AGENT_METHODS[:session_load]
    assert_equal "session/fork", Ask::ACP::Protocol::AGENT_METHODS[:session_fork]
    assert_equal "session/resume", Ask::ACP::Protocol::AGENT_METHODS[:session_resume]
    assert_equal "session/close", Ask::ACP::Protocol::AGENT_METHODS[:session_close]
    assert_equal "session/cancel", Ask::ACP::Protocol::AGENT_METHODS[:session_cancel]
    assert_equal "fs/read_text_file", Ask::ACP::Protocol::CLIENT_METHODS[:fs_read_text_file]
    assert_equal "fs/write_text_file", Ask::ACP::Protocol::CLIENT_METHODS[:fs_write_text_file]
  end

  # ── Client tests (using a mock subprocess) ──

  def test_client_initializes
    client = client_with_mock
    assert_kind_of Ask::ACP::Client, client
    refute client.running?
  end

  def test_client_start_stop
    client = client_with_mock
    client.start
    assert client.running?
    client.stop
    refute client.running?
  end

  def test_client_raises_without_start
    client = Ask::ACP::Client.new(command: ["/usr/bin/true"])
    assert_raises(Ask::ACP::Error) { client.request("test", {}) }
  end

  def test_client_raises_without_initialize
    client = client_with_mock
    client.start
    assert_raises(Ask::ACP::Error) { client.session_new(cwd: "/tmp") }
  end

  def test_normalize_session
    result = { "session" => { "id" => "sess_1", "status" => "running" } }
    client = Ask::ACP::Client.new(command: ["/usr/bin/true"])
    norm = client.send(:normalize_session, result)
    assert_equal "sess_1", norm[:id]
    assert_equal "running", norm[:status]
  end

  def test_normalize_session_without_wrapper
    result = { "id" => "sess_1", "status" => "completed" }
    client = Ask::ACP::Client.new(command: ["/usr/bin/true"])
    norm = client.send(:normalize_session, result)
    assert_equal "sess_1", norm[:id]
  end

  # ── Server tests ──

  def test_server_registers_default_methods
    server = Ask::ACP::Server.new
    assert server.respond_to?(:run, true)
  end

  def test_server_handles_initialize
    server = Ask::ACP::Server.new
    output = capture_stdout do
      server.send(:handle, {
        "jsonrpc" => "2.0", "id" => 1,
        "method" => "initialize",
        "params" => { "protocolVersion" => 1, "clientInfo" => { "name" => "test" } }
      })
    end
    assert_includes output, '"jsonrpc":"2.0"'
    assert_includes output, '"id":1'
  end

  def test_server_handles_unknown_method
    server = Ask::ACP::Server.new
    output = capture_stdout do
      server.send(:handle, {
        "jsonrpc" => "2.0", "id" => 1,
        "method" => "unknown/method"
      })
    end
    assert_includes output, '"code":-32601'
    assert_includes output, "Unknown method"
  end

  def test_server_handles_session_new
    server = Ask::ACP::Server.new
    output = capture_stdout do
      server.send(:handle, {
        "jsonrpc" => "2.0", "id" => 1,
        "method" => "session/new",
        "params" => { "cwd" => "/tmp" }
      })
    end
    assert_includes output, '"session"'
    assert_includes output, '"id"'
  end

  def test_server_sends_text_delta
    server = Ask::ACP::Server.new
    output = capture_stdout do
      server.send(:handle, {
        "jsonrpc" => "2.0", "id" => 1,
        "method" => "session/prompt",
        "params" => { "sessionId" => "sess_1", "input" => "hello" }
      })
    end
    assert_includes output, '"result"'
  end

  def test_server_handles_prompt_and_cancel
    server = Ask::ACP::Server.new
    output = capture_stdout do
      server.send(:handle, {
        "jsonrpc" => "2.0", "id" => 1,
        "method" => "session/cancel",
        "params" => { "sessionId" => "sess_1" }
      })
    end
    assert_includes output, '"id":1'
  end

  private

  def client_with_mock
    Ask::ACP::Client.new(command: ["/usr/bin/true"], request_timeout: 0.1)
  end

  def capture_stdout
    orig = $stdout
    $stdout = StringIO.new
    yield
    $stdout.rewind
    $stdout.read
  ensure
    $stdout = orig
  end
end
