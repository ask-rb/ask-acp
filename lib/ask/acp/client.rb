# frozen_string_literal: true

require "json"
require "open3"

module Ask
  module ACP
    # ACP client that connects to a coding agent over stdio using JSON-RPC 2.0.
    #
    # Spawns the agent CLI as a subprocess and communicates via stdin/stdout.
    # Supports all ACP methods: initialize, session/new, session/prompt, etc.
    #
    # @example
    #   client = Ask::ACP::Client.new(command: ["codex", "acp"])
    #   client.start
    #   result = client.initialize!(name: "askoda", version: "0.1.0")
    #   session = client.session_new(cwd: "/tmp")
    #   client.session_prompt(session[:id], "Hello") { |event| puts event }
    #   client.stop
    class Client
      attr_reader :command, :running

      def initialize(command:, request_timeout: 30.0)
        @command = command
        @request_timeout = request_timeout
        @stdin = nil
        @next_id = 1
        @pending = {}
        @event_handlers = []
        @running = false
        @mutex = Mutex.new
        @initialized = false
      end

      # Start the agent subprocess and begin reading stdout.
      def start
        @mutex.synchronize do
          return if @running
          @stdin, stdout, stderr, @wait_thr = Open3.popen3(*@command)

          @stdout_thread = Thread.new(stdout) do |io|
            io.each_line do |line|
              line = line.strip
              next if line.empty?
              handle_message(Protocol.parse(line))
            end
          end

          # Drain stderr to prevent deadlocks
          Thread.new(stderr) { |io| io.each_line { |_| } }

          @running = true
        end
      end

      # Stop the agent subprocess.
      def stop
        @mutex.synchronize do
          return unless @running
          @running = false
          @initialized = false
          @stdin&.close rescue nil
          @stdout_thread&.join(3) rescue nil
          Process.kill("TERM", @wait_thr.pid) rescue nil
          @wait_thr&.join(5) rescue nil
          @stdin = nil
          @pending.each_value { |f| f[:error] = Error.new("process exited"); f[:done] = true; f[:condition].signal }
          @pending.clear
        end
      end

      def running?
        @running && @wait_thr&.alive?
      end

      # Register a handler for incoming notifications (client methods from agent).
      def on_notification(&handler)
        @mutex.synchronize { @event_handlers << handler }
      end

      # ── ACP Methods ──

      # Initialize handshake. Must be called first.
      def initialize!(client_name:, client_version:, capabilities: {})
        result = request(Protocol::AGENT_METHODS[:initialize], {
          protocolVersion: Protocol::PROTOCOL_VERSION,
          clientInfo: { name: client_name, version: client_version },
          capabilities: capabilities
        })
        @initialized = true
        result
      end

      # Authenticate with the agent (if required).
      def authenticate(token:, scheme: "bearer")
        request(Protocol::AGENT_METHODS[:authenticate], {
          credentials: { scheme: scheme, token: token }
        })
      end

      # Create a new session in the given working directory.
      # Returns { id:, status:, created_at: }.
      def session_new(cwd: ".", model: nil, tools: nil)
        ensure_initialized!
        params = { cwd: cwd, mcpServers: [] }
        params[:model] = model if model
        result = request(Protocol::AGENT_METHODS[:session_new], params)
        normalize_session(result)
      end

      # Load an existing session by ID.
      def session_load(session_id)
        ensure_initialized!
        result = request(Protocol::AGENT_METHODS[:session_load], { sessionId: session_id })
        normalize_session(result)
      end

      # List sessions.
      def session_list(cwd: nil)
        ensure_initialized!
        params = {}
        params[:cwd] = cwd if cwd
        result = request(Protocol::AGENT_METHODS[:session_list], params)
        (result["sessions"] || result[:sessions] || []).map { |s| normalize_session(s) }
      end

      # Fork a session from an existing one.
      def session_fork(session_id)
        ensure_initialized!
        result = request(Protocol::AGENT_METHODS[:session_fork], { sessionId: session_id })
        normalize_session(result)
      end

      # Resume a session.
      def session_resume(session_id)
        ensure_initialized!
        result = request(Protocol::AGENT_METHODS[:session_resume], { sessionId: session_id })
        normalize_session(result)
      end

      # Close a session.
      def session_close(session_id)
        ensure_initialized!
        request(Protocol::AGENT_METHODS[:session_close], { sessionId: session_id })
      end

      # Send a prompt to a session and stream events via the block.
      # The prompt is automatically wrapped in a ContentBlock array if given
      # as a plain string.
      #
      # @yield [Hash] event with :method and :params
      # @return [Hash] the final session/prompt response
      def session_prompt(session_id, prompt, timeout: nil, &block)
        ensure_initialized!
        prompt_blocks = prompt.is_a?(Array) ? prompt : [{ type: "text", text: prompt.to_s }]
        params = { sessionId: session_id, prompt: prompt_blocks }
        if block
          # Register a temporary handler for streaming events
          handler = ->(msg) { block.call(method: msg["method"], params: msg["params"] || {}) if msg["method"] }
          on_notification(&handler)
          begin
            request(Protocol::AGENT_METHODS[:session_prompt], params, timeout: timeout)
          ensure
            @mutex.synchronize { @event_handlers.delete(handler) }
          end
        else
          request(Protocol::AGENT_METHODS[:session_prompt], params, timeout: timeout)
        end
      end

      # Cancel the current prompt execution.
      def session_cancel(session_id)
        ensure_initialized!
        request(Protocol::AGENT_METHODS[:session_cancel], { sessionId: session_id })
      end

      # Set a config option on a session.
      def session_set_config_option(session_id, key, value)
        ensure_initialized!
        request(Protocol::AGENT_METHODS[:session_set_config_option], {
          sessionId: session_id, key: key, value: value
        })
      end

      # Set the mode on a session.
      def session_set_mode(session_id, mode)
        ensure_initialized!
        request(Protocol::AGENT_METHODS[:session_set_mode], {
          sessionId: session_id, mode: mode
        })
      end

      # Set the model on a session.
      def session_set_model(session_id, provider:, model:)
        ensure_initialized!
        request(Protocol::AGENT_METHODS[:session_set_model], {
          sessionId: session_id, provider: provider, model: model
        })
      end

      # Send a JSON-RPC request and wait for the response.
      def request(method, params = nil, timeout: nil)
        ensure_running!
        future = { done: false, result: nil, error: nil, condition: ConditionVariable.new }

        @mutex.synchronize do
          id = @next_id
          @next_id += 1
          @pending[id] = future
          write(Protocol.build_request(method, params, id: id))
        end

        timeout ||= @request_timeout
        deadline = Time.now + timeout

        @mutex.synchronize do
          until future[:done]
            remaining = deadline - Time.now
            raise TimeoutError, "Request timed out after #{timeout}s" if remaining <= 0
            future[:condition].wait(@mutex, remaining)
          end
        end

        raise future[:error] if future[:error]
        future[:result]
      end

      private

      def ensure_running!
        raise Error, "ACP client not started. Call #start first." unless running?
      end

      def ensure_initialized!
        ensure_running!
        raise Error, "ACP not initialized. Call #initialize! first." unless @initialized
      end

      def write(msg)
        @stdin&.puts(JSON.generate(msg))
        @stdin&.flush
      end

      def handle_message(msg)
        return unless msg

        # Response to a pending request
        if msg.key?("id")
          rid = msg["id"]
          future = nil
          @mutex.synchronize { future = @pending.delete(rid) }

          if future
            @mutex.synchronize do
              if msg.key?("error")
                err = msg["error"]
                future[:error] = Error.new("[#{err["code"]}] #{err["message"]}")
              elsif msg.key?("result")
                future[:result] = msg["result"]
              else
                future[:error] = Error.new("No result or error")
              end
              future[:done] = true
              future[:condition].signal
            end
            return
          end
        end

        # Notification or event (no id or unmatched id)
        dispatch_event(msg)
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
