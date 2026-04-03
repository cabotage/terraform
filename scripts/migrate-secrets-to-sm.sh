#!/bin/sh
set -e

usage() {
  echo "Usage: $0 --prefix <sm-prefix> --region <aws-region> --secrets-dir <path> [--profile <aws-profile>] [--dry-run]"
  echo
  echo "Migrates secrets from local filesystem to AWS Secrets Manager."
  echo
  echo "Options:"
  echo "  --prefix       SM prefix (e.g. cabotage/prod-cluster)"
  echo "  --region       AWS region"
  echo "  --secrets-dir  Path to the secrets directory (e.g. .secrets/default)"
  echo "  --profile      AWS CLI profile (optional)"
  echo "  --dry-run      Show what would be done without making changes"
  echo "  --verify-only  Only verify existing SM secrets match disk"
  exit 1
}

PREFIX=""
REGION=""
SECRETS_DIR=""
PROFILE=""
DRY_RUN=false
VERIFY_ONLY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)      PREFIX="$2"; shift 2 ;;
    --region)      REGION="$2"; shift 2 ;;
    --secrets-dir) SECRETS_DIR="$2"; shift 2 ;;
    --profile)     PROFILE="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --verify-only) VERIFY_ONLY=true; shift ;;
    *) usage ;;
  esac
done

if [ -z "$PREFIX" ] || [ -z "$REGION" ] || [ -z "$SECRETS_DIR" ]; then
  usage
fi

if [ ! -d "$SECRETS_DIR" ]; then
  echo "ERROR: secrets directory not found: $SECRETS_DIR" >&2
  exit 1
fi

AWS_ARGS="--region $REGION"
if [ -n "$PROFILE" ]; then
  AWS_ARGS="$AWS_ARGS --profile $PROFILE"
fi

# All known secret files
SECRETS="
ca.key
ca.crt
vault-bootstrap-token
vault-unseal-key
vault-recovery-key
consul-bootstrap-token
github-app-private-key.pem
github-webhook-secret
github-app-client-id
github-app-client-secret
dockerhub-username
dockerhub-token
slack-client-id
slack-client-secret
discord-client-id
discord-client-secret
discord-bot-token
"

upload_secret() {
  _name="$1"
  _file="$SECRETS_DIR/$_name"
  _sid="$PREFIX/$_name"

  if [ ! -f "$_file" ]; then
    return
  fi

  _value=$(cat "$_file")
  if [ -z "$_value" ]; then
    echo "  SKIP $_name (empty file)"
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "  WOULD upload $_name ($(wc -c < "$_file" | tr -d ' ') bytes)"
    return
  fi

  # Check if SM secret exists
  if aws secretsmanager describe-secret --secret-id "$_sid" $AWS_ARGS >/dev/null 2>&1; then
    aws secretsmanager put-secret-value \
      --secret-id "$_sid" \
      --secret-string "$_value" \
      $AWS_ARGS >/dev/null
    echo "  UPDATED $_name"
  else
    aws secretsmanager create-secret \
      --name "$_sid" \
      --secret-string "$_value" \
      $AWS_ARGS >/dev/null
    echo "  CREATED $_name"
  fi
}

verify_secret() {
  _name="$1"
  _file="$SECRETS_DIR/$_name"
  _sid="$PREFIX/$_name"

  if [ ! -f "$_file" ]; then
    return
  fi

  _disk=$(cat "$_file")
  if [ -z "$_disk" ]; then
    return
  fi

  _sm=$(aws secretsmanager get-secret-value \
    --secret-id "$_sid" \
    --query 'SecretString' --output text \
    $AWS_ARGS 2>/dev/null || echo "")

  if [ -z "$_sm" ]; then
    echo "  MISSING $_name (not in SM)"
    VERIFY_FAILED=true
  elif [ "$_disk" = "$_sm" ]; then
    echo "  OK      $_name"
  else
    echo "  MISMATCH $_name"
    VERIFY_FAILED=true
  fi
}

# --- Main ---

FOUND=0
for name in $SECRETS; do
  [ -f "$SECRETS_DIR/$name" ] && FOUND=$((FOUND + 1))
done
echo "Found $FOUND secret files in $SECRETS_DIR"
echo "Target: $PREFIX/* in $REGION"
[ -n "$PROFILE" ] && echo "Profile: $PROFILE"
echo

if [ "$VERIFY_ONLY" = true ]; then
  echo "=== Verifying SM secrets match disk ==="
  VERIFY_FAILED=false
  for name in $SECRETS; do
    verify_secret "$name"
  done
  echo
  if [ "$VERIFY_FAILED" = true ]; then
    echo "VERIFICATION FAILED — some secrets are missing or mismatched."
    exit 1
  else
    echo "All secrets verified OK."
  fi
  exit 0
fi

if [ "$DRY_RUN" = true ]; then
  echo "=== Dry run — no changes will be made ==="
fi

echo "=== Uploading secrets ==="
for name in $SECRETS; do
  upload_secret "$name"
done
echo

if [ "$DRY_RUN" = true ]; then
  echo "Dry run complete. Re-run without --dry-run to apply."
  exit 0
fi

echo "=== Verifying ==="
VERIFY_FAILED=false
for name in $SECRETS; do
  verify_secret "$name"
done
echo

if [ "$VERIFY_FAILED" = true ]; then
  echo "WARNING: Verification found issues. Check output above."
  exit 1
fi

echo "Migration complete. Next steps:"
echo "  1. Set secrets_manager_prefix = \"$PREFIX\" in your Terraform config"
echo "  2. Set secrets_manager_region = \"$REGION\""
[ -n "$PROFILE" ] && echo "  3. Set secrets_manager_profile = \"$PROFILE\""
echo "  4. Run terraform plan — should show no changes"
echo "  5. Run terraform apply"
echo "  6. Keep $SECRETS_DIR as backup until confident"
