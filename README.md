# ask-acp

[![Gem Version](https://badge.fury.io/rb/ask-acp.svg)](https://badge.fury.io/rb/ask-acp)

A Ruby implementation of the Agent Client Protocol (ACP): JSON-RPC 2.0 over
stdio, following the v0.11.3 protocol schema. It provides a client that drives
an ACP-compliant coding agent as a subprocess, a server base class for making
a Ruby agent speak ACP, and a replay client for deterministic testing.

## Installation

```ruby
gem "ask-acp"
```

## Quick Start

### Client: drive an ACP agent subprocess

```ruby
require "ask-acp"

client = Ask::ACP::Client.new(command: ["codex", "acp"])
client.start
client.initialize!(client_name: "my-app", client_version: "0.1.0")

session = client.session_new(cwd: "/tmp")

# Stream prompt events as they arrive
client.session_prompt(session[:id], "Hello!") do |event|
  puts "#{event[:method]}: #{event[:params]}"
end

client.stop
```

### Server: speak ACP as a Ruby agent

```ruby
class MyAgent < Ask::ACP::Server
  def handle_session_new(params)
    { session: { id: SecureRandom.uuid, status: "running" } }
  end
end

MyAgent.new.run
```

## Key entry points

- `Ask::ACP::Client` - spawns an agent CLI subprocess with Open3 and speaks
  ACP over stdio. Methods: `initialize!`, `authenticate`, `session_new`,
  `session_load`, `session_list`, `session_fork`, `session_resume`,
  `session_close`, `session_prompt` (streams events via a block),
  `session_cancel`, `session_set_config_option`, `session_set_mode`,
  `session_set_model`, `start`, `stop`.
- `Ask::ACP::Server` - base class to subclass; implement `handle_*` methods
  and run with `.run`.
- `Ask::ACP::ReplayClient` - replays pre-recorded JSONL interactions from a
  fixture file. No subprocess; instant, deterministic responses.
- `Ask::ACP::Protocol` - message builders and constants:
  `AGENT_METHODS`, `CLIENT_METHODS`, `PROMPT_EVENTS`, `STATUSES`,
  `PROTOCOL_VERSION`.
- `Ask::ACP::Error` and `Ask::ACP::TimeoutError` - errors raised by the
  client.

## Full documentation

The full ask-rb documentation lives at https://ask-rb.github.io/ask-docs.
[Reference: Gem Index](https://ask-rb.github.io/ask-docs/reference/gems)
covers ask-acp in depth. API reference:
https://ask-rb.github.io/ask-docs/reference/api.

## Development

```
bundle install
bundle exec ruby -Itest test/acp_test.rb
```

## License

MIT
