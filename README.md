# zoracle

A pure **[Zsh](https://www.zsh.org/)** AI agent that lives in your terminal.

Zoracle is an agentic, function-calling LLM assistant written almost entirely
in zsh. It streams a chat with any **OpenAI-compatible** LLM endpoint, and when
the model wants real-world context it can read/write files, run commands,
search the web, and send messages — all through native tool calls executed by
zsh functions.

> **Note:** The core agent is 100% zsh. A couple of the *tools* (page
> extraction, exact text patching) delegate to `perl`/`python` when available,
> and `sandbox` shells out to Docker. That's just what we have on hand.

---

## Features

- **Streaming chat** with reasoning, content, and tool calls rendered live
  (dim reasoning, colored delimiters).
- **Native function calling** — OpenAI-style `tool_calls` with JSON schemas;
  results are fed back to the model as `role: "tool"` messages.
- **Agent loop** — the agent keeps calling tools until the task is done
  (configurable iteration cap).
- **Interactive REPL** — zsh-line-editor powered prompt with up/down history,
  terminal tab-completion, `/clear`, `/history`, `/model`, `/exit`.
- **Or one-shot mode** — `zoracle "question"` from any shell.
- **12+ tools** — web search, page reading, file read/write/patch, shell exec,
  sandboxed execution, code search, messaging, time grounding.
- **Workspace jail** — file & search tools are confined to a configurable
  workspace root.
- **Safe by default** — arbitrary shell execution (`exec`) is disabled unless
  you flip a kill switch; untrusted commands can be run in a network-less
  Docker sandbox instead.
- **Any model, any host** — points at any `v1/chat/completions` server
  (llama.cpp, vLLM, LiteLLM, OpenAI, ...).

## Requirements

Everything is plain shell + the usual POSIX toolbelt.

| Required  | Optional (deepen functionality)      |
|-----------|-------------------------------------|
| `zsh`     | `rg` (faster search)                |
| `jq`      | `python` (HTML-to-text, file patch) |
| `curl`    | `lynx` (best HTML-to-text quality)  |
| `timeout` | `docker` (sandbox tool)             |
| `date`, `awk`, `sed`, `grep`, `find`, `stdbuf` |          |

## Installation

Clone (or copy) the repository into `~/.zoracle`:

```zsh
git clone <this-repo> ~/.zoracle
```

Then source the entrypoint from your `~/.zshrc`:

```zsh
source ~/.zoracle/init.zsh
```

Run from the same shell session afterwards:

```zsh
zoracle "what files are in this repo?"   # one-shot
zoracle                                  # interactive session
```

## Configuration

Copy `config.example.zsh` to `config.zsh` and edit it, or export the same
variables before sourcing `init.zsh`:

```zsh
# config.zsh
ZORACLE_LLM_BASE_URL="http://127.0.0.1:1919"   # any OpenAI-compatible endpoint
ZORACLE_LLM_MODEL="minicpm5-2b"
ZORACLE_LLM_API_KEY="not-needed"
```

`config.zsh` is git-ignored, so it's a safe home for anything sensitive.

### Useful settings

| Variable                                | Default            | Purpose                                   |
|-----------------------------------------|--------------------|-------------------------------------------|
| `ZORACLE_LLM_BASE_URL`                  | `http://127.0.0.1:1919` | LLM endpoint (OpenAI-compatible)      |
| `ZORACLE_LLM_MODEL`                     | `minicpm5-2b`      | Model name sent in the request (`/model` overrides per session) |
| `ZORACLE_AGENT_MAX_ITERATIONS`          | `16`               | Cap on tool-call rounds                   |
| `ZORACLE_TOOL_OUTPUT_MAX_CHARS`         | `4000`             | Tool output truncated for the model       |
| `ZORACLE_WORKSPACE_ROOT`                | `$PWD`             | Jail for file/exec/search tools           |
| `ZORACLE_EXEC_ENABLED`                  | `0`                | Kill switch for the `exec` tool           |
| `ZORACLE_SANDBOX_ENABLED`               | `1`                | Kill switch for the `sandbox` tool        |
| `ZORACLE_SANDBOX_IMAGE`                 | `alpine:3.20`      | Image used by the `sandbox` tool          |

### Optional API keys

- `TAVILY_API_KEY` **or** `SERPAPI_KEY` — web search (Tavily preferred, free tier)
- `SLACK_WEBHOOK_URL` / `DISCORD_WEBHOOK_URL` / `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` — notifications

## Tools

| Tool            | What it does                                          |
|-----------------|--------------------------------------------------------|
| `search`        | Web search via Tavily / SerpAPI                        |
| `fetch`         | Fetch a URL and extract readable text                  |
| `time`          | Current time, relative offsets, epoch conversions      |
| `read_file`     | Read a file with numbered lines (capped)               |
| `write_file`    | Create / overwrite a file                              |
| `append_file`   | Append to a file                                       |
| `patch_file`    | Literal search-and-replace edit in a file              |
| `grep`          | Regex search across files (ripgrep, with fallback)     |
| `find`          | Find files by glob name pattern                        |
| `exec`          | Run a shell command in the workspace (opt-in)          |
| `sandbox`       | Run a command in an isolated, network-less container   |
| `notify`        | Send Slack / Discord / Telegram messages               |

Tools are exposed to the model using JSON schemas (OpenAI function-calling
format) and dispatched by an explicit router written in zsh.

## Interactive mode

```
[Agent Interactive Mode] Type "/exit" or "/quit" to leave.

You: list the *.zsh files and show the longest one
     [Agent Intercept] Executing tool: find with args: {"pattern":"*.zsh"}...
     [Tool Result] find:
     ...
[Agent System] 1 tool result(s) fed back to model. Resuming thought stream...
```

| Command      | Action                            |
|--------------|-----------------------------------|
| `/exit`, `/quit` | Leave the session             |
| `/clear`     | Reset the conversation history    |
| `/history`   | Dump the raw conversation JSON    |
| `/model <name>` | Switch the LLM model mid-session |

`Ctrl+D` on an empty line also exits; `Ctrl+C` interrupts gracefully; `Tab`
completes the internal commands; up/down arrows walk your prompt history.

## Safety notes

- **`exec` is disabled by default** (`ZORACLE_EXEC_ENABLED=0`). Set it to `1`
  in `config.zsh` only if you trust the model and the code it runs.
- The `sandbox` tool runs commands in a throwaway Docker container with
  networking disabled and resource limits — the intended home for untrusted
  code.
- File and search tools jail all paths to `ZORACLE_WORKSPACE_ROOT`; paths that
  would escape the jail are rejected.

## Development

```zsh
# Offline smoke tests (core + router + tools)
zsh ~/.zoracle/tests/smoke.zsh

# End-to-end test against a scripted mock LLM server
# (exercises native tool calling end-to-end: tools key, tool_calls, results)
zsh ~/.zoracle/tests/e2e.zsh
```

Tests run against `tests/mock_llm.py`, a small OpenAI-compatible streaming
server that scripts a tool-calling turn, so no model or network is needed.
