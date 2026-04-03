# Shared helpers for cabotage bootstrap scripts.
# Source this at the top of every script:
#   . "$(dirname "$0")/_lib.sh"
#
# Requires KUBE_CONTEXT to be set.
# Optional: SECRETS_MANAGER_PREFIX and SECRETS_MANAGER_REGION for AWS Secrets Manager mode.

KUBECTL="kubectl --context ${KUBE_CONTEXT}"

# --- Secrets backend abstraction ---
# When SECRETS_MANAGER_PREFIX is set, secrets are stored in AWS Secrets Manager.
# Otherwise, they are stored as files in SECRETS_DIR.

if [ -n "${SECRETS_MANAGER_PREFIX:-}" ] && ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI is required when using Secrets Manager" >&2
  exit 1
fi

# Build common AWS CLI args (profile + region)
_aws_sm() {
  _args="--region ${SECRETS_MANAGER_REGION}"
  if [ -n "${SECRETS_MANAGER_PROFILE:-}" ]; then
    _args="$_args --profile ${SECRETS_MANAGER_PROFILE}"
  fi
  aws secretsmanager "$@" $_args
}

# secret_read <name>
# Returns the secret value, or empty string if not found.
secret_read() {
  _name="$1"
  if [ -n "${SECRETS_MANAGER_PREFIX:-}" ]; then
    _aws_sm get-secret-value \
      --secret-id "${SECRETS_MANAGER_PREFIX}/${_name}" \
      --query 'SecretString' --output text 2>/dev/null || echo ""
  else
    if [ -f "${SECRETS_DIR}/${_name}" ]; then
      cat "${SECRETS_DIR}/${_name}"
    else
      echo ""
    fi
  fi
}

# secret_write <name> <value>
# Writes a secret value. Creates the SM secret if it doesn't exist.
secret_write() {
  _name="$1"; _value="$2"
  if [ -n "${SECRETS_MANAGER_PREFIX:-}" ]; then
    _sid="${SECRETS_MANAGER_PREFIX}/${_name}"
    if ! _aws_sm describe-secret --secret-id "$_sid" >/dev/null 2>&1; then
      _aws_sm create-secret \
        --name "$_sid" \
        --secret-string "${_value}" >/dev/null
    else
      _aws_sm put-secret-value \
        --secret-id "$_sid" \
        --secret-string "${_value}" >/dev/null
    fi
  else
    mkdir -p "${SECRETS_DIR}"
    printf '%s' "${_value}" > "${SECRETS_DIR}/${_name}"
    chmod 600 "${SECRETS_DIR}/${_name}"
  fi
}

# secret_exists <name>
# Returns 0 if the secret has a non-empty value, 1 otherwise.
secret_exists() {
  _name="$1"
  if [ -n "${SECRETS_MANAGER_PREFIX:-}" ]; then
    _val=$(_aws_sm get-secret-value \
      --secret-id "${SECRETS_MANAGER_PREFIX}/${_name}" \
      --query 'SecretString' --output text 2>/dev/null || echo "")
    [ -n "$_val" ]
  else
    [ -f "${SECRETS_DIR}/${_name}" ]
  fi
}

# secret_read_to_file <name> <dest_path>
# Reads a secret and writes it to a local file (for tools that need file input).
# Caller is responsible for cleanup. Returns 1 if secret is empty/missing.
secret_read_to_file() {
  _name="$1"; _dest="$2"
  _content=$(secret_read "$_name")
  if [ -z "$_content" ]; then
    return 1
  fi
  printf '%s' "$_content" > "$_dest"
  chmod 600 "$_dest"
}

# secret_write_from_file <name> <source_file>
# Writes the contents of a file as a secret value.
secret_write_from_file() {
  _name="$1"; _src="$2"
  secret_write "$_name" "$(cat "$_src")"
}

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

# ensure_secret <secret_name> <namespace>
# Create the secret if it doesn't exist yet.
ensure_secret() {
  $KUBECTL get secret "$1" -n "$2" >/dev/null 2>&1 || \
    $KUBECTL create secret generic "$1" --namespace "$2"
}

# ensure_secret_key <secret_name> <namespace> <key> <gen_cmd>
# Generate a secret key only if it doesn't already exist.
ensure_secret_key() {
  _secret="$1"; _ns="$2"; _key="$3"; _gen_cmd="$4"
  _existing=$($KUBECTL get secret "$_secret" -n "$_ns" -o jsonpath="{.data.${_key}}" 2>/dev/null || true)
  if [ -n "$_existing" ]; then
    echo "  $_key: preserved"
  else
    _value=$(eval "$_gen_cmd")
    $KUBECTL patch secret "$_secret" -n "$_ns" \
      -p "{\"data\":{\"${_key}\":\"$(printf '%s' "$_value" | base64)\"}}"
    echo "  $_key: generated"
  fi
}

# set_secret_key <secret_name> <namespace> <key> <value>
# Always set a secret key to the given value.
set_secret_key() {
  _secret="$1"; _ns="$2"; _key="$3"; _value="$4"
  $KUBECTL patch secret "$_secret" -n "$_ns" \
    -p "{\"data\":{\"${_key}\":\"$(printf '%s' "$_value" | base64)\"}}"
  echo "  $_key: updated"
}
