#!/usr/bin/env bash
# fm-ollama-usage.sh - read ollama-cloud usage windows from ollama.com.
#
# TEMPORARY bridge owned by this home: it exists so the fleet can see
# ollama-cloud headroom before quota-axi ships an ollama provider.
# RETIRE this script once quota-axi releases provider `ollama` (upstream issue
# kunchenguid/quota-axi#86, PR kunchenguid/quota-axi#169) and reads the key there.
# The ollama.com/api/usage payload carries no reset timestamp.
# This bridge therefore reports only the fraction already used, never when the
# window recovers.
#
# Usage:
#   fm-ollama-usage.sh             print the TOON usage block
#   fm-ollama-usage.sh --json      print the stable machine JSON
#
# Credentials follow the upstream provider contract exactly, in order:
#   1. the OLLAMA_API_KEY environment variable
#   2. the `ollama-cloud` api_key entry in $PI_CODING_AGENT_DIR/auth.json
#      (default ~/.pi/agent/auth.json), of shape {"type":"api_key","key":...}
# The Pi auth store is the only file-based source.
# ~/.pi/agent/models.json is deliberately never read, so this bridge cannot
# teach the fleet a non-standard credential source.
# The key is never printed, in whole or in part, not even in error output.
# Fail-closed: exactly one diagnostic line distinguishes a missing credential,
# an HTTP failure (with its status code), and a payload that cannot be read.
# Read-only: exactly one GET https://ollama.com/api/usage with an Accept
# application/json header, a Bearer authorization header, and a 15-second
# timeout bound.
set -eu

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "${BASH_SOURCE[0]}"
  exit 2
}

MODE=toon
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) MODE=json; shift ;;
    -h|--help|help) usage ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[ "$#" -eq 0 ] || usage

KEY=
CREDENTIAL_SOURCE=
if [ -n "${OLLAMA_API_KEY:-}" ]; then
  KEY=$OLLAMA_API_KEY
  CREDENTIAL_SOURCE='env OLLAMA_API_KEY'
else
  AUTH_DIR=${PI_CODING_AGENT_DIR:-"$HOME/.pi/agent"}
  AUTH_FILE="$AUTH_DIR/auth.json"
  if [ -f "$AUTH_FILE" ]; then
    KEY=$(python3 - "$AUTH_FILE" 2>/dev/null <<'PY' || true
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        store = json.load(handle)
    entry = store.get("ollama-cloud")
    if isinstance(entry, dict) and entry.get("type") == "api_key":
        key = entry.get("key")
        if isinstance(key, str) and key:
            print(key)
except Exception:
    pass
PY
    )
    if [ -n "$KEY" ]; then
      CREDENTIAL_SOURCE="$AUTH_FILE ollama-cloud"
    fi
  fi
fi
[ -n "$KEY" ] || die "no ollama-usage credential (set OLLAMA_API_KEY or add an ollama-cloud api_key entry to the Pi auth store)"

TMP=$(mktemp "${TMPDIR:-/tmp}/fm-ollama-usage.XXXXXX") || die "cannot create a temp file"
trap 'rm -f "$TMP"' EXIT

# One read-only request. The status code is captured from stdout while the
# body goes to the temp file, so an HTTP failure keeps its code and a
# transport failure stays visibly distinct from an unreadable payload.
CODE=$(curl --silent --max-time 15 \
  --write-out '%{http_code}' \
  --output "$TMP" \
  --header 'Accept: application/json' \
  --header "Authorization: Bearer $KEY" \
  --url 'https://ollama.com/api/usage' 2>/dev/null) || CODE=000
case "${CODE:-}" in
  2??) : ;;
  000|'') die "ollama usage request failed (transport or timeout error)" ;;
  *) die "ollama usage request failed with HTTP ${CODE}" ;;
esac

if ! python3 - "$TMP" "$MODE" "$CREDENTIAL_SOURCE" <<'PY'
import datetime
import json
import sys

payload_path, mode, credential = sys.argv[1], sys.argv[2], sys.argv[3]


def fail():
    sys.exit(1)


def is_num(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def parse_window(window):
    if not isinstance(window, dict):
        fail()
    usage = window.get("usage")
    if not is_num(usage) or usage < 0 or usage > 1:
        fail()
    raw_models = window.get("models", [])
    if not isinstance(raw_models, list):
        fail()
    models = []
    for model in raw_models:
        if not isinstance(model, dict):
            fail()
        name = model.get("name")
        count = model.get("request_count")
        if not isinstance(name, str) or not name:
            fail()
        if not is_num(count) or count < 0 or count != int(count):
            fail()
        models.append({"name": name, "request_count": int(count)})
    return {
        "usage": float(usage),
        "usagePercent": round(float(usage) * 100, 3),
        "models": models,
    }


try:
    with open(payload_path, encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        fail()
    limits = payload.get("limits")
    if not isinstance(limits, dict):
        fail()
    session = parse_window(limits.get("session"))
    weekly = parse_window(limits.get("weekly"))
except Exception:
    fail()

generated_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
if generated_at.endswith("+00:00"):
    generated_at = generated_at[:-6] + "Z"
description = "Report ollama-cloud session and weekly usage for routing-aware agents"
windows = [("session", session), ("weekly", weekly)]
help_lines = [
    "Bridge: retires when quota-axi ships provider ollama (issue kunchenguid/quota-axi#86, PR kunchenguid/quota-axi#169).",
    "Payload has no reset timestamp: this reports fraction used, not recovery time.",
    "Run `fm-ollama-usage.sh --json` for the stable machine schema.",
]


def toon(value):
    text = str(value)
    if "," in text or '"' in text or text != text.strip():
        return json.dumps(text)
    return text


def render_toon():
    out = []
    out.append("bin: fm-ollama-usage.sh")
    out.append("description: " + description)
    out.append('generatedAt: "%s"' % generated_at)
    out.append("credential: " + credential)
    out.append("limits[2]{window,usage,usagePercent}:")
    for name, window in windows:
        out.append("  %s,%s,%s" % (name, toon(window["usage"]), toon(window["usagePercent"])))
    models = [(name, model) for name, window in windows for model in window["models"]]
    out.append("models[%d]{window,model,request_count}:" % len(models))
    for name, model in models:
        out.append("  %s,%s,%s" % (name, toon(model["name"]), str(model["request_count"])))
    out.append("help[%d]:" % len(help_lines))
    out.extend("  " + line for line in help_lines)
    print("\n".join(out))


def render_json():
    document = {
        "bin": "fm-ollama-usage.sh",
        "schema": "fm-ollama-usage.v1",
        "description": description,
        "generatedAt": generated_at,
        "credential": {"source": credential},
        "limits": {"session": session, "weekly": weekly},
    }
    print(json.dumps(document, indent=2, sort_keys=True))


if mode == "json":
    render_json()
else:
    render_toon()
PY
then
  die "cannot parse ollama usage payload"
fi
