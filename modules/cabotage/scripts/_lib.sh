# Shared helpers for cabotage bootstrap scripts.
# Source this at the top of every script:
#   . "$(dirname "$0")/_lib.sh"
#
# Requires KUBE_CONTEXT to be set.

KUBECTL="kubectl --context ${KUBE_CONTEXT}"

# retry <max_attempts> <delay_seconds> <command...>
# Retries a command up to max_attempts times with a fixed delay.
retry() {
  max=$1; shift
  delay=$1; shift
  attempt=1
  while [ $attempt -le "$max" ]; do
    if "$@"; then
      return 0
    fi
    echo "  Attempt $attempt/$max failed, retrying in ${delay}s..." >&2
    attempt=$((attempt + 1))
    sleep "$delay"
  done
  echo "  Failed after $max attempts: $*" >&2
  return 1
}

# wait_for <timeout_seconds> <interval_seconds> <command...>
# Polls until command succeeds or timeout is reached.
wait_for() {
  timeout=$1; shift
  interval=$1; shift
  elapsed=0
  while [ $elapsed -lt "$timeout" ]; do
    if "$@" 2>/dev/null; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  echo "  Timed out after ${timeout}s waiting for: $*" >&2
  return 1
}

# curl_api <curl_args...>
# Wrapper around curl that shows the response body on failure.
# Use instead of bare `curl -sf`.
curl_api() {
  TMPFILE=$(mktemp)
  HTTP_CODE=$(curl -s -w '%{http_code}' -o "$TMPFILE" "$@")
  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    cat "$TMPFILE"
    rm -f "$TMPFILE"
    return 0
  else
    echo "  HTTP $HTTP_CODE from: curl $*" >&2
    cat "$TMPFILE" >&2
    rm -f "$TMPFILE"
    return 1
  fi
}

# kill_port <port>
# Kill any process listening on the given port.
kill_port() {
  lsof -ti :"$1" | xargs kill 2>/dev/null || true
  sleep 1
}
