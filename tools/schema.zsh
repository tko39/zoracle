#!/usr/bin/zsh
# ~/.zoracle/tools/schema.zsh — JSON Schemas for the tools advertised to the
# model through the request "tools" key (OpenAI function-calling format).
#
# Kept in sync with tools/router.zsh: every entry below maps to an
# _zoracle_execute_tool_json branch, and its arguments map 1:1 onto the parameters
# of the corresponding tool_* function.
#
# "exec" is only advertised when ZORACLE_EXEC_ENABLED != 0 (kill switch).

_zoracle_get_tools_json() {
  local exec_on=false
  [[ "${ZORACLE_EXEC_ENABLED:-0}" != 0 ]] && exec_on=true
  jq -c --argjson exec_on "$exec_on" \
    'map(select(.function.name != "exec" or $exec_on))' <<'EOF'
[
  {
    "type": "function",
    "function": {
      "name": "search",
      "description": "Web search for live information. Returns TITLE/URL/SNIPPET entries.",
      "parameters": {
        "type": "object",
        "properties": {
          "query": { "type": "string", "description": "Search query" }
        },
        "required": ["query"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "fetch",
      "description": "Extract readable text from a web page (follows redirects).",
      "parameters": {
        "type": "object",
        "properties": {
          "url": { "type": "string", "description": "Full URL, e.g. https://example.com" }
        },
        "required": ["url"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "time",
      "description": "Date/time grounding: current local time + epoch, parse a time spec, or diff two epochs.",
      "parameters": {
        "type": "object",
        "properties": {
          "spec": {
            "type": "string",
            "description": "One of: \"now\" | unix epoch like \"1789145737\" | GNU date relative spec like \"+2 hours\" or \"tomorrow\" | \"diff <epoch1> <epoch2>\". Defaults to \"now\"."
          }
        }
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "read_file",
      "description": "Read a text file; returns numbered lines.",
      "parameters": {
        "type": "object",
        "properties": {
          "path": { "type": "string", "description": "File path (relative to the workspace root, or absolute inside it)" },
          "max_lines": { "type": "integer", "description": "Maximum lines to show (default 400)" }
        },
        "required": ["path"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "write_file",
      "description": "Create or overwrite a file. Content is written exactly as given.",
      "parameters": {
        "type": "object",
        "properties": {
          "path": { "type": "string", "description": "File path" },
          "content": { "type": "string", "description": "Exact file content; may contain newlines" }
        },
        "required": ["path", "content"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "append_file",
      "description": "Append text to a file (created if missing), keeping existing content.",
      "parameters": {
        "type": "object",
        "properties": {
          "path": { "type": "string", "description": "File path" },
          "content": { "type": "string", "description": "Exact text to append" }
        },
        "required": ["path", "content"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "patch_file",
      "description": "Edit a file by literally replacing the first exact occurrence of old_text with new_text.",
      "parameters": {
        "type": "object",
        "properties": {
          "path": { "type": "string", "description": "File path" },
          "old_text": { "type": "string", "description": "Exact existing text to find" },
          "new_text": { "type": "string", "description": "Exact replacement text" }
        },
        "required": ["path", "old_text", "new_text"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "exec",
      "description": "Run a shell command directly in the workspace (trusted).",
      "parameters": {
        "type": "object",
        "properties": {
          "command": { "type": "string", "description": "Shell command to run" }
        },
        "required": ["command"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "sandbox",
      "description": "Run a shell command isolated in a Docker container (network disabled).",
      "parameters": {
        "type": "object",
        "properties": {
          "command": { "type": "string", "description": "Shell command to run" }
        },
        "required": ["command"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "find",
      "description": "Locate files by glob name pattern.",
      "parameters": {
        "type": "object",
        "properties": {
          "pattern": { "type": "string", "description": "Glob pattern, e.g. *.py" },
          "dir": { "type": "string", "description": "Optional directory to search (default: workspace root)" }
        },
        "required": ["pattern"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "grep",
      "description": "Search file contents with a regex pattern.",
      "parameters": {
        "type": "object",
        "properties": {
          "pattern": { "type": "string", "description": "Regex pattern" },
          "dir": { "type": "string", "description": "Optional directory to search (default: workspace root)" }
        },
        "required": ["pattern"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "notify",
      "description": "Send a message via a messaging platform.",
      "parameters": {
        "type": "object",
        "properties": {
          "platform": { "type": "string", "enum": ["slack", "discord", "telegram"], "description": "Target platform" },
          "message": { "type": "string", "description": "Message text" }
        },
        "required": ["platform", "message"]
      }
    }
  }
]
EOF
}