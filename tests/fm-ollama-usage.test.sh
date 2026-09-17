#!/usr/bin/env bash
# Behavioral tests for bin/fm-ollama-usage.sh.
# Drives the public argv interface with a fake curl, never the network.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

OLLAMA_SCRIPT="$ROOT/bin/fm-ollama-usage.sh"
TMP_ROOT=$(fm_test_tmproot fm-ollama-usage)

FAKEBIN=$(fm_fakebin "$TMP_ROOT")
FIXTURE="$TMP_ROOT/usage.json"
MALFORMED="$TMP_ROOT/malformed.json"
AUTH_DIR="$TMP_ROOT/auth"
AUTH_FILE="$AUTH_DIR/auth.json"
EMPTY_DIR="$TMP_ROOT/empty-auth"
ENV_KEY="ollama-test-secret-abc123"
STORE_KEY="store-secret-xyz789"

mkdir -p "$AUTH_DIR" "$EMPTY_DIR"
cat > "$AUTH_FILE" <<JSON
{"ollama-cloud": {"type": "api_key", "key": "$STORE_KEY"}, "other": {"type": "api_key", "key": "unrelated-secret-000"}}
JSON
cat > "$FIXTURE" <<'JSON'
{
  "activity": {"cost": "0.00000"},
  "limits": {
    "session": {"usage": 0.062, "models": [
      {"name": "deepseek-v4.1-flash", "request_count": 73},
      {"name": "deepseek-v4-flash:0731", "request_count": 30}
    ]},
    "weekly": {"usage": 0.114, "models": [
      {"name": "deepseek-v4.1-flash", "request_count": 725},
      {"name": "deepseek-v4-flash:0731", "request_count": 160},
      {"name": "minimax-m3", "request_count": 28},
      {"name": "web search", "request_count": 2}
    ]}
  }
}
JSON
printf 'this is not json\r\n' > "$MALFORMED"

cat > "$FAKEBIN/curl" <<'SH'
#!/usr/bin/env bash
# Fake curl: records the request, writes the fixture body, prints the code.
set -u
status=${FAKE_CURL_STATUS:-200}
out=
url=
prev=
for arg in "$@"; do
  if [ "$prev" = "--output" ]; then
    out=$arg
  elif [ "$prev" = "--url" ]; then
    url=$arg
  elif [ "$prev" = "--header" ] && printf '%s\n' "$arg" | grep -q '^Authorization: Bearer '; then
    printf '%s\n' "$arg" >> "${FAKE_CURL_HEADERS_FILE:-/dev/null}"
  fi
  prev=$arg
done
printf '%s\n' "$url" >> "${FAKE_CURL_URLS_FILE:-/dev/null}"
if [ "$status" = "200" ]; then
  if [ -n "${FAKE_CURL_BODY:-}" ]; then
    cat "$FAKE_CURL_BODY" > "$out"
  fi
else
  printf '%s\n' '{"error":"boom"}' > "$out"
fi
printf '%s\n' "$status"
SH
chmod +x "$FAKEBIN/curl"

run_script() {
  # run_script <name> [extra env assignments...]
  local name=$1
  shift
  env FAKE_CURL_BODY="$FIXTURE" FAKE_CURL_HEADERS_FILE="$TMP_ROOT/$name.headers" \
    FAKE_CURL_URLS_FILE="$TMP_ROOT/$name.urls" OLLAMA_API_KEY="$ENV_KEY" \
    PI_CODING_AGENT_DIR="$AUTH_DIR" PATH="$FAKEBIN:$PATH" \
    "$@" "$OLLAMA_SCRIPT" > "$TMP_ROOT/$name.out" 2> "$TMP_ROOT/$name.err"
  cat "$TMP_ROOT/$name.out" "$TMP_ROOT/$name.err"
}

test_store_wins_over_env_toon() {
  # Both sources hold DIFFERENT keys; the auth store must win (issue
  # kunchenguid/quota-axi#86), so the store key is the bearer token.
  local output
  output=$(run_script store-wins)
  assert_contains "$output" "limits[2]{window,usage,usagePercent}:" "TOON omitted the limits header"
  assert_contains "$output" "  session,0.062,6.2" "TOON session row wrong"
  assert_contains "$output" "  weekly,0.114,11.4" "TOON weekly row wrong"
  assert_contains "$output" "models[6]{window,model,request_count}:" "TOON omitted the models header"
  assert_contains "$output" "  session,deepseek-v4.1-flash,73" "TOON session model row wrong"
  assert_contains "$output" "  weekly,minimax-m3,28" "TOON weekly model row wrong"
  assert_contains "$output" "  weekly,web search,2" "TOON spaced model row wrong"
  assert_contains "$output" "credential: $AUTH_FILE ollama-cloud" \
    "TOON did not name the auth-store credential"
  assert_contains "$output" "Bridge: retires when quota-axi ships provider ollama" \
    "TOON omitted the retirement condition"
  assert_equals "" "$(cat "$TMP_ROOT/store-wins.err")" "store-wins run wrote to stderr"
  assert_equals 1 "$(wc -l < "$TMP_ROOT/store-wins.urls" | tr -d ' ')" "store-wins run made more than one request"
  assert_grep 'https://ollama.com/api/usage' "$TMP_ROOT/store-wins.urls" \
    "store-wins run requested the wrong URL"
  assert_grep "Authorization: Bearer $STORE_KEY" "$TMP_ROOT/store-wins.headers" \
    "auth store did not win over the env credential"
  assert_no_grep "Authorization: Bearer $ENV_KEY" "$TMP_ROOT/store-wins.headers" \
    "env credential was sent despite the auth-store key"
  assert_not_contains "$output" "$STORE_KEY" "store-wins run leaked the store key"
  assert_not_contains "$output" "$ENV_KEY" "store-wins run leaked the env key"
  pass "auth store outranks a differing env key and renders the full TOON block"
}

test_env_fallback_toon() {
  # No ollama-cloud entry in the auth store, so OLLAMA_API_KEY is the fallback.
  local output
  output=$(run_script env-fallback PI_CODING_AGENT_DIR="$EMPTY_DIR")
  assert_contains "$output" "credential: env OLLAMA_API_KEY" \
    "TOON did not name the env credential"
  assert_grep "Authorization: Bearer $ENV_KEY" "$TMP_ROOT/env-fallback.headers" \
    "env fallback did not send the env key as the bearer token"
  assert_no_grep "Authorization: Bearer $STORE_KEY" "$TMP_ROOT/env-fallback.headers" \
    "store key was sent with no auth-store entry"
  assert_equals 1 "$(wc -l < "$TMP_ROOT/env-fallback.urls" | tr -d ' ')" \
    "env fallback run made more than one request"
  assert_not_contains "$output" "$ENV_KEY" "env fallback run leaked the api key"
  pass "env credential is the fallback when the auth store has no ollama-cloud entry"
}

test_store_credential_json() {
  local output
  output=$(env -u OLLAMA_API_KEY FAKE_CURL_BODY="$FIXTURE" \
    FAKE_CURL_HEADERS_FILE="$TMP_ROOT/store.headers" \
    FAKE_CURL_URLS_FILE="$TMP_ROOT/store.urls" PI_CODING_AGENT_DIR="$AUTH_DIR" \
    PATH="$FAKEBIN:$PATH" "$OLLAMA_SCRIPT" --json 2> "$TMP_ROOT/store.err")
  printf '%s\n' "$output" | jq -e '
    .bin == "fm-ollama-usage.sh" and
    .schema == "fm-ollama-usage.v1" and
    (.generatedAt | type == "string" and length > 0) and
    .credential.source == "'"$AUTH_FILE"' ollama-cloud" and
    .limits.session.usage == 0.062 and
    .limits.session.usagePercent == 6.2 and
    .limits.weekly.usage == 0.114 and
    .limits.weekly.usagePercent == 11.4 and
    (.limits.session.models | length) == 2 and
    (.limits.weekly.models | length) == 4 and
    (.limits.weekly.models[] | select(.name == "deepseek-v4.1-flash") | .request_count) == 725
  ' >/dev/null || fail "store credential JSON schema assertion failed: $output"
  assert_not_contains "$output" "$STORE_KEY" "store credential run leaked the store key"
  assert_not_contains "$output" "$ENV_KEY" "store credential run leaked the env key"
  assert_equals "" "$(cat "$TMP_ROOT/store.err")" "store credential run wrote to stderr"
  assert_grep "Authorization: Bearer $STORE_KEY" "$TMP_ROOT/store.headers" \
    "store credential was not sent as the bearer token"
  pass "auth-store credential sends the store key and renders stable JSON"
}

test_missing_credential() {
  local err
  set +e
  err=$(env -u OLLAMA_API_KEY PI_CODING_AGENT_DIR="$EMPTY_DIR" PATH="$FAKEBIN:$PATH" \
    "$OLLAMA_SCRIPT" 2>&1 > "$TMP_ROOT/nocred.out")
  local code=$?
  set -e
  expect_code 1 "$code" "missing credential"
  assert_equals "" "$(cat "$TMP_ROOT/nocred.out")" "missing credential run wrote to stdout"
  assert_contains "$err" "no ollama-usage credential" "missing credential diagnostic absent"
  assert_absent "$TMP_ROOT/nocred.urls" "missing credential run still invoked curl"
  assert_not_contains "$err" "$ENV_KEY" "missing credential run leaked an env key"
  pass "missing credential fails closed and never reaches the network"
}

test_http_error() {
  local err
  set +e
  err=$(env FAKE_CURL_STATUS=500 FAKE_CURL_BODY="$MALFORMED" \
    FAKE_CURL_HEADERS_FILE="$TMP_ROOT/http.headers" \
    FAKE_CURL_URLS_FILE="$TMP_ROOT/http.urls" OLLAMA_API_KEY="$ENV_KEY" \
    PI_CODING_AGENT_DIR="$AUTH_DIR" PATH="$FAKEBIN:$PATH" \
    "$OLLAMA_SCRIPT" 2>&1)
  local code=$?
  set -e
  expect_code 1 "$code" "HTTP error"
  assert_contains "$err" "HTTP 500" "HTTP error diagnostic omitted the status code"
  assert_not_contains "$err" "$ENV_KEY" "HTTP error run leaked the api key"
  assert_equals 1 "$(wc -l < "$TMP_ROOT/http.urls" | tr -d ' ')" "HTTP error run made more than one request"
  pass "HTTP failure fails closed naming the status code"
}

test_malformed_payload() {
  local err
  set +e
  err=$(env FAKE_CURL_BODY="$MALFORMED" FAKE_CURL_HEADERS_FILE="$TMP_ROOT/malformed.headers" \
    FAKE_CURL_URLS_FILE="$TMP_ROOT/malformed.urls" OLLAMA_API_KEY="$ENV_KEY" \
    PI_CODING_AGENT_DIR="$AUTH_DIR" PATH="$FAKEBIN:$PATH" \
    "$OLLAMA_SCRIPT" 2>&1)
  local code=$?
  set -e
  expect_code 1 "$code" "malformed payload"
  assert_contains "$err" "cannot parse ollama usage payload" "unreadable payload diagnostic wrong"
  assert_not_contains "$err" "$ENV_KEY" "malformed payload run leaked the api key"
  pass "unreadable payload fails closed with one diagnostic line"
}

test_help() {
  local help
  set +e
  help=$("$OLLAMA_SCRIPT" --help 2>&1)
  local code=$?
  set -e
  expect_code 2 "$code" "--help exit code"
  assert_contains "$help" "TEMPORARY bridge" "help omitted the bridge status"
  assert_contains "$help" "RETIRE this script once quota-axi releases provider" \
    "help omitted the retirement condition"
  assert_contains "$help" "no reset timestamp" "help omitted the reset-timestamp note"
  assert_not_contains "$help" "set -u" "help leaked executable source"
  pass "help renders only the complete header"
}

test_store_wins_over_env_toon
test_env_fallback_toon
test_store_credential_json
test_missing_credential
test_http_error
test_malformed_payload
test_help

printf '# all fm-ollama-usage tests passed\n'
