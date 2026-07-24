# frozen_string_literal: true

require "json"

module Ask
  module ACP
    # ACP client that replays pre-recorded interactions from a fixture file.
    #
    # Like VCR for stdio — no subprocess, instant response, deterministic.
    # Records are newline-delimited JSON with format:
    #   {"request": {...}}    ← request sent to agent
    #   {"response": {...}}   ← response from agent (or mock)
    #   {"notification": {...}} ← async notification from agent
    #
    # @example
    #   client = Ask::ACP::ReplayClient.new(fixture: "test/fixtures/opencode_session.jsonl")
    #   client.start
    #   client.initialize!(client_name: "test", client_version: "0.1.0")
    class ReplayClient
      attr_reader :fixture_path, :running

      def initialize(fixture_path:)
        @fixture_path = fixture_path
        @events = []
        @index = 0
        @running = false
        @initialized = false
        @event_handlers = []
        @pending = {}
        @next_id = 1
        @mutex = Mutex.new
      end

      def start
        load_fixture
        @running = true
      end

      def stop
        @running = false
        @initialized = false
      end

      def running?
        @running
      end

      def on_notification(&handler)
        @mutex.synchronize { @event_handlers << handler }
      end

      # ── ACP Methods (same interface as Client) ──

      def initialize!(client_name:, client_version:, capabilities: {})
        @initialized = true
        make_request("initialize", {
          protocolVersion: 1, clientInfo: { name: client_name, version: client_version }, capabilities: capabilities
        })
      end

      def session_new(cwd: ".", model: nil)
        ensure_initialized!
        params = { cwd: cwd, mcpServers: [] }
        params[:model] = model if model
        normalize_session(make_request(Protocol::AGENT_METHODS[:session_new], params))
      end

      def session_load(session_id)
        ensure_initialized!
        result = make_request(Protocol::AGENT_METHODS[:session_load], { sessionId: session_id })
        normalize_session(result)
      end

      def session_list(cwd: nil)
        ensure_initialized!
        params = {}
        params[:cwd] = cwd if cwd
        result = make_request(Protocol::AGENT_METHODS[:session_list], params)
        (result["sessions"] || result[:sessions] || []).map { |s| normalize_session(s) }
      end

      def session_resume(session_id)
        ensure_initialized!
        result = make_request(Protocol::AGENT_METHODS[:session_resume], { sessionId: session_id })
        normalize_session(result)
      end

      def session_close(session_id)
        ensure_initialized!
        make_request(Protocol::AGENT_METHODS[:session_close], { sessionId: session_id })
      end

      def session_prompt(session_id, prompt, timeout: nil, &block)
        ensure_initialized!
        prompt_blocks = prompt.is_a?(Array) ? prompt : [{ type: "text", text: prompt.to_s }]
        params = { sessionId: session_id, prompt: prompt_blocks }

        # Dispatch any notifications before the response
        while @index < @events.length
          event = @events[@index]
          break if event.key?("response")
          if event.key?("notification")
            dispatch_event(event["notification"])
          end
          @index += 1
        end

        # Get the response
        event = @events[@index]
        @index += 1
        if event && event["response"]
          result = event["response"]["result"]
          error = event["response"]["error"]
          raise Error.new("[#{error["code"]}] #{error["message"]}") if error
          result
        else
          { "status" => "completed" }
        end
      end

      private

      def ensure_initialized!
        raise Error, "ReplayClient not started. Call #start first." unless @running
        raise Error, "Not initialized. Call #initialize! first." unless @initialized
      end

      def load_fixture
        @events = []
        File.readlines(@fixture_path).each do |line|
          line = line.strip
          next if line.empty?
          @events << JSON.parse(line)
        end
        @index = 0
      rescue => e
        raise Error, "Failed to load fixture #{@fixture_path}: #{e.message}"
      end

      def make_request(method, params)
        # Look for the next response event matching this method
        while @index < @events.length
          event = @events[@index]
          @index += 1

          if event["response"]
            result = event["response"]["result"]
            error = event["response"]["error"]
            raise Error.new("[#{error["code"]}] #{error["message"]}") if error
            return result
          end
        end
        {}
      end

      def dispatch_event(msg)
        @event_handlers.dup.each { |h| h.call(msg) rescue nil }
      end

      def normalize_session(result)
        s = result["session"] || result[:session] || result
        {
          id: s["id"] || s["sessionId"],
          status: s["status"] || "unknown",
          created_at: s["createdAt"] || s["created_at"]
        }
      end
    end
  end
end
