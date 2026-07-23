# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# Integration tests that spawn a real Ruby ACP agent as a subprocess.
class ACPIntegrationTest < Minitest::Test
  MOCK_AGENT = File.expand_path("../fixtures/mock_acp_agent.rb", __dir__)

  def setup
    @tmpdir = Dir.mktmpdir("acp_test")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_initialize_handshake
    client = Ask::ACP::Client.new(command: ["ruby", MOCK_AGENT], request_timeout: 5)
    client.start
    result = client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    assert result.is_a?(Hash), "Initialize should return a Hash"
    assert result["serverInfo"] || result[:serverInfo], "Should have serverInfo"
    client.stop
  end

  def test_session_new
    client = Ask::ACP::Client.new(command: ["ruby", MOCK_AGENT], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    session = client.session_new(cwd: @tmpdir)
    assert session[:id], "Should return a session id"
    assert session[:status], "Should return a status"
    client.stop
  end

  def test_full_prompt_flow
    client = Ask::ACP::Client.new(command: ["ruby", MOCK_AGENT], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    session = client.session_new(cwd: @tmpdir)
    assert session[:id], "Session should be created"

    result = client.request("session/prompt", { sessionId: session[:id], input: "Say hello" })
    assert result, "Prompt should return a result"
    client.stop
  end

  def test_session_list
    client = Ask::ACP::Client.new(command: ["ruby", MOCK_AGENT], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    sessions = client.session_list
    assert_kind_of Array, sessions
    client.stop
  end

  def test_session_close
    client = Ask::ACP::Client.new(command: ["ruby", MOCK_AGENT], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    session = client.session_new(cwd: @tmpdir)
    result = client.session_close(session[:id])
    assert result.is_a?(Hash), "Close should return a result"
    client.stop
  end

  def test_error_on_unknown_method
    client = Ask::ACP::Client.new(command: ["ruby", MOCK_AGENT], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    assert_raises(Ask::ACP::Error) do
      client.request("nonexistent/method", {})
    end
    client.stop
  end

  def test_logout
    client = Ask::ACP::Client.new(command: ["ruby", MOCK_AGENT], request_timeout: 5)
    client.start
    client.initialize!(client_name: "askoda-test", client_version: "0.1.0")
    result = client.request("logout", {})
    assert result.is_a?(Hash)
    client.stop
  end
end
