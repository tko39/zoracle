#!/usr/bin/zsh
# ~/.zoracle/tools/web.zsh — Web search (Tavily/SerpAPI) + page extraction

# Shared rate limiter for external web services
_zoracle_web_rate_limit() {
  local current_time=$SECONDS
  local elapsed=$(( current_time - _ZORACLE_LAST_REQUEST_EPOCH_SECONDS ))
  if (( elapsed < ZORACLE_REQUEST_MIN_INTERVAL_SECONDS )); then
    sleep $(( ZORACLE_REQUEST_MIN_INTERVAL_SECONDS - elapsed ))
  fi
  _ZORACLE_LAST_REQUEST_EPOCH_SECONDS=$SECONDS
}

_zoracle_tool_web_search() {
  local query="${*:-}"
  if [[ -z "$query" ]]; then
    printf '{"error": "No query provided"}\n'
    return 1
  fi

  _zoracle_web_rate_limit

  local response parsed
  if [[ -n "${TAVILY_API_KEY:-}" ]]; then
    local payload
    payload=$(jq -cn --arg q "$query" '{
      query: $q, search_depth: "basic",
      include_answer: false, include_images: false, max_results: 5
    }')
    response=$(curl -sS -m 15 -X POST "https://api.tavily.com/search" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $TAVILY_API_KEY" \
      -d "$payload") || return 1
    parsed=$(jq -r '
      .results // [] |
      map("TITLE: " + .title + "\nURL: " + .url + "\nSNIPPET: " + .content) |
      join("\n---\n")
    ' <<<"$response")
  elif [[ -n "${SERPAPI_KEY:-}" ]]; then
    response=$(curl -sS -m 15 -G "https://serpapi.com/search" \
      --data-urlencode "q=$query" \
      --data-urlencode "api_key=$SERPAPI_KEY") || return 1
    parsed=$(jq -r '
      .organic_results // [] |
      map("TITLE: " + .title + "\nURL: " + .link + "\nSNIPPET: " + (.snippet // "")) |
      join("\n---\n")
    ' <<<"$response")
  else
    printf 'ERROR: no search provider key set. Export TAVILY_API_KEY (https://tavily.com, free tier) or SERPAPI_KEY.\n'
    return 1
  fi

  if [[ -z "$parsed" ]]; then
    printf 'No search results found for "%s".\n' "$query"
  else
    printf '%s\n' "$parsed"
  fi
}

# ---------- HTML-to-text extraction (layered: lynx / python stdlib / perl) ----------

# Layer 1: lynx -dump (best quality, if installed)
_zoracle_web_html_to_text_lynx() {
  local raw_html="$1"
  local tmpf
  tmpf=$(mktemp) || return 2
  printf '%s' "$raw_html" > "$tmpf"
  lynx -dump -nolist "$tmpf" 2>/dev/null
  local rc=$?
  rm -f "$tmpf"
  (( rc == 0 )) || return 2
}

# Layer 2: Python 3 stdlib (html.parser) — decodes entities, strips scripts/styles,
# renders simple structure as Markdown-ish text. No third-party deps.
_zoracle_web_html_to_text_python() {
  local raw_html="$1"
  _ZORACLE_HTML_INPUT="$raw_html" python - <<'PY'
import html.parser, os, sys

class Extractor(html.parser.HTMLParser):
    SKIP = {"script", "style", "noscript", "template", "head"}
    BLOCK = {"p","div","section","article","header","footer","main","nav",
             "br","li","tr","h1","h2","h3","h4","h5","h6","blockquote","pre",
             "table","ul","ol","form"}
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip_depth = 0
        self.href = None
        self.parts = []
    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip_depth += 1
        elif not self.skip_depth:
            if tag == "a":
                self.href = dict(attrs).get("href")
            elif tag == "pre":
                self.parts.append("\n```\n")
            elif tag == "li":
                self.parts.append("\n- ")
            elif tag == "tr":
                self.parts.append("\n")
            elif tag in ("td", "th"):
                self.parts.append(" | ")
            elif tag in ("h1","h2","h3","h4","h5","h6"):
                self.parts.append("\n\n## ")
    def handle_endtag(self, tag):
        if tag in self.SKIP:
            self.skip_depth = max(0, self.skip_depth - 1)
        elif not self.skip_depth:
            if tag == "a" and self.href:
                self.parts.append(" (" + self.href + ")")
                self.href = None
            elif tag == "pre":
                self.parts.append("\n```\n")
            elif tag in self.BLOCK:
                self.parts.append("\n")
    def handle_data(self, data):
        if not self.skip_depth:
            self.parts.append(data)

p = Extractor()
try:
    p.feed(os.environ.get("_ZORACLE_HTML_INPUT", ""))
    p.close()
except Exception:
    pass
lines = []
for line in "".join(p.parts).splitlines():
    line = " ".join(line.split())
    if line:
        lines.append(line)
sys.stdout.reconfigure(errors="replace")
print("\n\n".join(lines))
PY
}

# Layer 3: perl + sed fallback (no python/lynx available)
_zoracle_web_html_to_text_perl() {
  local raw_html="$1"
  printf '%s' "$raw_html" |
    sed -e '/<[Ss][Cc][Rr][Ii][Pp][Tt]/,/<\/[Ss][Cc][Rr][Ii][Pp][Tt]>/d' \
        -e '/<[Ss][Tt][Yy][Ll][Ee]/,/<\/[Ss][Tt][Yy][Ll][Ee]>/d' \
        -e 's/<[^>]*>/ /g' |
    perl -MHTML::Entities -0777 -pe '$_ = decode_entities($_);'
}

_zoracle_tool_fetch_page() {
  local url="${1:-}"
  if [[ -z "$url" ]]; then
    printf '{"error": "No URL provided"}\n'
    return 1
  fi

  _zoracle_web_rate_limit

  local raw_html
  raw_html=$(curl -sS -L -m 10 -A "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0" "$url") || {
    printf '{"error": "Failed to fetch page at %s"}\n' "$url"
    return 1
  }

  local text="" layer="none"

  if command -v lynx >/dev/null 2>&1; then
    text=$(_zoracle_web_html_to_text_lynx "$raw_html") && layer="lynx"
  fi

  if [[ -z "$text" ]] && command -v python >/dev/null 2>&1; then
    text=$(_zoracle_web_html_to_text_python "$raw_html") && layer="python"
  fi

  if [[ -z "$text" ]]; then
    text=$(_zoracle_web_html_to_text_perl "$raw_html") && layer="perl"
  fi

  if [[ -z "$text" ]]; then
    printf '{"error": "Failed to extract text from %s (all extractors failed)"}\n' "$url"
    return 1
  fi

  # Collapse whitespace runs and cap output for the model context window
  text=$(printf '%s' "$text" | tr -s ' \t\r' ' ' | sed 's/^ //; s/ $//')

  local max="${ZORACLE_FETCH_MAX_CHARS:-4000}"
  if (( ${#text} > max )); then
    printf '[extractor: %s]\n%s\n[truncated at %d chars — page continues]\n' "$layer" "${text[1,$max]}" "$max"
  elif (( ${#text} < 100 )); then
    printf '[extractor: %s]\n%s\n[note: very short page — it may be JS-rendered or a login/error page]\n' "$layer" "$text"
  else
    printf '[extractor: %s]\n%s\n' "$layer" "$text"
  fi
}
