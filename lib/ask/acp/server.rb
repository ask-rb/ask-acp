# frozen_string_literal: true

require "json"

module Ask
  module ACP
    # ACP server that lets a Ruby agent speak the Agent Client Protocol over stdio.
    #
    # Handles the JSON-RPC 2.0 transport, method dispatch, and streaming responses.
    # Subclass and implement the method handlers you need.
    #
    # @example
    #   class MyAgent < Ask::ACP::Server
    #     def handle_initialize(params)
    #       { protocolVersion: 1, serverInfo: { name: "my-agent", version: "0.1.0" } }
    #     end
    #
    #     def handle_session_new(params)
    #       { session: { id: SecureRandom.uuid, status: "running" } }
    #     end
    #   end
    #
    #   MyAgent.new.run
    class Server
      def initialize
        @methods = {}
        register_defaults
      end

      # Start reading from stdin and processing requests.
      def run
        $stdin.each_line do |line|
          line = line.strip
          next if line.empty?
          handle(Protocol.parse(line))
        end
      rescue => e
        $stderr.puts "ACP server error: #{e.message}"
      end

      private

      def register_defaults
        register("initialize") do |params|
          handle_initialize(params)
        end

        register("session/new") do |params|
          handle_session_new(params)
        end

        register("session/load") do |params|
          handle_session_load(params)
        end

        register("session/list") do |params|
          handle_session_list(params)
        end

        register("session/resume") do |params|
          handle_session_resume(params)
        end

        register("session/close") do |params|
          handle_session_close(params)
        end

        register("session/prompt") do |params|
          handle_session_prompt(params)
        end

        register("session/cancel") do |params|
          handle_session_cancel(params)
        end
      end

      # Default handlers — override in subclasses.

      def handle_initialize(params)
        { protocolVersion: Protocol::PROTOCOL_VERSION, capabilities: {}, serverInfo: { name: "ask-acp", version: VERSION } }
      end

      def handle_session_new(params)
        require "securerandom"
        id = SecureRandom.uuid
        { session: { id: id, status: "running" } }
      end

      def handle_session_load(params)
        { session: { id: params["sessionId"], status: "running" } }
      end

      def handle_session_list(params)
        { sessions: [] }
      end

      def handle_session_resume(params)
        { session: { id: params["sessionId"], status: "running" } }
      end

      def handle_session_close(params)
        {}
      end

      def handle_session_prompt(params)
        # Default: stream back a completion event immediately
        send_text_delta(params["sessionId"], "Hello from ACP server!")
        send_event("turn_complete", { sessionId: params["sessionId"] })
        { status: "completed" }
      end

      def handle_session_cancel(params)
        {}
      end

      def register(method, &handler)
        @methods[method] = handler
      end

      def handle(msg)
        return unless msg

        if msg.key?("id")
          id = msg["id"]
          method = msg["method"]
          params = msg["params"] || {}

          handler = @methods[method]
          if handler
            begin
              result = handler.call(params)
              write(Protocol.build_response(id, result))
            rescue => e
              write(Protocol.build_error(id, -32_600, e.message))
            end
          else
            write(Protocol.build_error(id, -32_601, "Unknown method: #{method}"))
          end
        end
      end

      def write(msg)
        $stdout.puts(JSON.generate(msg))
        $stdout.flush
      end

      def send_event(method, params)
        write(Protocol.build_notification(method, params))
      end

      def send_text_delta(session_id, content)
        send_event("text", { sessionId: session_id, content: content })
      end
    end
  end
end
