# frozen_string_literal: true

require "json"

module Ask
  module ACP
    # Protocol constants and message helpers for the Agent Client Protocol (ACP).
    #
    # ACP uses JSON-RPC 2.0 over stdio (newline-delimited JSON).
    # Protocol version: 1 (v0.11.3 schema)
    module Protocol
      PROTOCOL_VERSION = 1

      # Agent methods (client → agent)
      AGENT_METHODS = {
        initialize: "initialize",
        authenticate: "authenticate",
        logout: "logout",
        session_cancel: "session/cancel",
        session_close: "session/close",
        session_fork: "session/fork",
        session_list: "session/list",
        session_load: "session/load",
        session_new: "session/new",
        session_prompt: "session/prompt",
        session_resume: "session/resume",
        session_set_config_option: "session/set_config_option",
        session_set_mode: "session/set_mode",
        session_set_model: "session/set_model"
      }.freeze

      # Client methods (agent → client, for tool execution and elicitation)
      CLIENT_METHODS = {
        fs_read_text_file: "fs/read_text_file",
        fs_write_text_file: "fs/write_text_file",
        session_elicitation: "session/elicitation",
        session_elicitation_complete: "session/elicitation/complete",
        session_request_permission: "session/request_permission",
        session_update: "session/update",
        terminal_create: "terminal/create",
        terminal_kill: "terminal/kill",
        terminal_output: "terminal/output",
        terminal_release: "terminal/release",
        terminal_wait_for_exit: "terminal/wait_for_exit"
      }.freeze

      # Prompt response event types (streamed from session/prompt)
      PROMPT_EVENTS = {
        text: "text",
        tool_use: "tool_use",
        tool_result: "tool_result",
        turn_complete: "turn_complete",
        turn_failed: "turn_failed",
        session_update: "session/update",
        permission_request: "session/request_permission",
        elicitation: "session/elicitation"
      }.freeze

      STATUSES = {
        completed: "completed",
        failed: "failed",
        cancelled: "cancelled",
        in_progress: "in_progress"
      }.freeze

      # Build a JSON-RPC 2.0 request.
      def self.build_request(method, params = nil, id: nil)
        msg = { jsonrpc: "2.0", method: method }
        msg[:id] = id
        msg[:params] = params if params
        msg
      end

      # Build a JSON-RPC 2.0 notification (no id).
      def self.build_notification(method, params = nil)
        msg = { jsonrpc: "2.0", method: method }
        msg[:params] = params if params
        msg
      end

      # Build a JSON-RPC 2.0 success response.
      def self.build_response(id, result)
        { jsonrpc: "2.0", id: id, result: result }
      end

      # Build a JSON-RPC 2.0 error response.
      def self.build_error(id, code, message, data: nil)
        err = { code: code, message: message }
        err[:data] = data if data
        { jsonrpc: "2.0", id: id, error: err }
      end

      # Parse a JSON-RPC message from a line.
      # Returns a hash with string keys, or nil if invalid.
      def self.parse(line)
        return nil if line.nil? || line.strip.empty?
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      # Serialize a message to a JSON line (with newline).
      def self.serialize(msg)
        JSON.generate(msg) + "\n"
      end
    end
  end
end
