#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="run_agentroot_embed"
# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'USAGE'
Run a best-effort agentroot embedding pass with optional local llama-server bootstrapping.

Usage:
  run_agentroot_embed.sh --db <path/to/index.sqlite> [options]

Options:
  --db <path>          Path to agentroot sqlite DB (required)
  --output-dir <dir>   Directory for embed logs (default: <db-dir>)
  --model <path>       GGUF embedding model path
  --host <host>        Embedding server host (default: 127.0.0.1)
  --port <port>        Embedding server port (default: 8000)
  --force              Pass --force to agentroot embed
  --no-start-local     Do not auto-start llama-server on connection failures
  --download-model     Download default nomic GGUF if missing (off by default)
  --wait-seconds <n>   Max seconds to wait for local server health (default: 60)
  --keep-server        Keep locally-started llama-server running after completion
  --help               Show this help

Environment overrides:
  VIBE_CODE_AUDIT_EMBED_MODEL_PATH
  VIBE_CODE_AUDIT_EMBED_MODEL_URL
  VIBE_CODE_AUDIT_EMBED_HOST
  VIBE_CODE_AUDIT_EMBED_PORT
  VIBE_CODE_AUDIT_EMBED_START_LOCAL
  VIBE_CODE_AUDIT_EMBED_DOWNLOAD_MODEL
  VIBE_CODE_AUDIT_EMBED_WAIT_SECONDS
  VIBE_CODE_AUDIT_EMBED_KEEP_SERVER
  VIBE_CODE_AUDIT_EMBED_CTX_SIZE
  VIBE_CODE_AUDIT_EMBED_BATCH_SIZE
  VIBE_CODE_AUDIT_EMBED_UBATCH_SIZE
USAGE
}

health_url() {
  printf 'http://%s:%s/health' "$HOST" "$PORT"
}

health_ok() {
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi
  curl -fsS --max-time 2 "$(health_url)" >/dev/null 2>&1
}

wait_for_health() {
  elapsed=0
  while [ "$elapsed" -lt "$WAIT_SECONDS" ]; do
    if health_ok; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

download_model_if_needed() {
  [ -f "$MODEL_PATH" ] && return 0

  if [ "$DOWNLOAD_MODEL" -ne 1 ]; then
    return 1
  fi
  command -v curl >/dev/null 2>&1 || return 1

  mkdir -p "$(dirname "$MODEL_PATH")"
  log "Downloading embedding model to $MODEL_PATH"
  if ! curl -fsSL "$MODEL_URL" -o "$MODEL_PATH"; then
    warn "Model download failed from $MODEL_URL"
    return 1
  fi
  return 0
}

start_local_server() {
  command -v llama-server >/dev/null 2>&1 || return 1
  download_model_if_needed || [ -f "$MODEL_PATH" ] || return 1

  mkdir -p "$OUTPUT_DIR"
  log "Starting local llama-server on ${HOST}:${PORT}"

  llama-server \
    --embeddings \
    --model "$MODEL_PATH" \
    --port "$PORT" \
    --ctx-size "$LLAMA_CTX_SIZE" \
    --batch-size "$LLAMA_BATCH_SIZE" \
    --ubatch-size "$LLAMA_UBATCH_SIZE" >"$LLAMA_SERVER_LOG" 2>&1 &

  LLAMA_PID="$!"
  SERVER_STARTED=1
  if wait_for_health; then
    return 0
  fi

  warn "llama-server did not become healthy at $(health_url) within ${WAIT_SECONDS}s"
  warn "See $LLAMA_SERVER_LOG"
  return 1
}

run_embed() {
  log_path="$1"
  cmd=(agentroot embed)
  if [ "$FORCE" -eq 1 ]; then
    cmd+=(--force)
  fi
  if AGENTROOT_DB="$DB_PATH" "${cmd[@]}" >"$log_path" 2>&1; then
    return 0
  fi
  return 1
}

emit_result() {
  ok="$1"
  backend="$2"
  log_path="$3"
  printf 'EMBED_OK=%s\n' "$ok"
  printf 'EMBED_BACKEND=%s\n' "$backend"
  printf 'EMBED_LOG=%s\n' "$log_path"
  printf 'EMBED_UTF8_PANIC=%s\n' "$UTF8_PANIC"
  if [ "$SERVER_STARTED" -eq 1 ]; then
    printf 'EMBED_SERVER_LOG=%s\n' "$LLAMA_SERVER_LOG"
    printf 'EMBED_SERVER_PID=%s\n' "$LLAMA_PID"
  fi
}

cleanup() {
  if [ "$SERVER_STARTED" -eq 1 ] && [ -n "${LLAMA_PID:-}" ] && [ "$KEEP_SERVER" -ne 1 ]; then
    kill "$LLAMA_PID" >/dev/null 2>&1 || true
    LLAMA_PID=""
    SERVER_STARTED=0
  fi
}

# Parse persistent embed config from installer if present (safe line-by-line,
# never sourced as shell code to prevent command injection).
# EMBED_ENV_FILE is defined in _lib.sh; use that canonical constant.
if [ -f "$EMBED_ENV_FILE" ]; then
  # Snapshot which keys are already set in the environment before parsing,
  # so pre-existing env vars take precedence but later lines in the file
  # can still override earlier ones (last-occurrence-wins within the file).
  _env_preset=""
  for _env_k in VIBE_CODE_AUDIT_EMBED_MODEL_PATH VIBE_CODE_AUDIT_EMBED_MODEL_URL \
    VIBE_CODE_AUDIT_EMBED_HOST VIBE_CODE_AUDIT_EMBED_PORT \
    VIBE_CODE_AUDIT_EMBED_START_LOCAL VIBE_CODE_AUDIT_EMBED_DOWNLOAD_MODEL \
    VIBE_CODE_AUDIT_EMBED_WAIT_SECONDS VIBE_CODE_AUDIT_EMBED_KEEP_SERVER \
    VIBE_CODE_AUDIT_EMBED_CTX_SIZE VIBE_CODE_AUDIT_EMBED_BATCH_SIZE \
    VIBE_CODE_AUDIT_EMBED_UBATCH_SIZE; do
    if [ -n "${!_env_k+x}" ]; then
      _env_preset="${_env_preset}${_env_k} "
    fi
  done
  while IFS='=' read -r _env_key _env_value || [ -n "$_env_key" ]; do
    # Skip blank lines and comments
    case "$_env_key" in
      ''|\#*) continue ;;
    esac
    # Strip trailing carriage return from value (CRLF files)
    _env_value="${_env_value%$'\r'}"
    # Strip one layer of matching surrounding quotes
    case "$_env_value" in
      \"*\") _env_value="${_env_value#\"}"; _env_value="${_env_value%\"}" ;;
      \'*\') _env_value="${_env_value#\'}"; _env_value="${_env_value%\'}" ;;
    esac
    # Only accept whitelisted keys; defer to pre-existing env vars
    case "$_env_key" in
      VIBE_CODE_AUDIT_EMBED_MODEL_PATH|\
      VIBE_CODE_AUDIT_EMBED_MODEL_URL|\
      VIBE_CODE_AUDIT_EMBED_HOST|\
      VIBE_CODE_AUDIT_EMBED_PORT|\
      VIBE_CODE_AUDIT_EMBED_START_LOCAL|\
      VIBE_CODE_AUDIT_EMBED_DOWNLOAD_MODEL|\
      VIBE_CODE_AUDIT_EMBED_WAIT_SECONDS|\
      VIBE_CODE_AUDIT_EMBED_KEEP_SERVER|\
      VIBE_CODE_AUDIT_EMBED_CTX_SIZE|\
      VIBE_CODE_AUDIT_EMBED_BATCH_SIZE|\
      VIBE_CODE_AUDIT_EMBED_UBATCH_SIZE)
        # Skip if this key was already set before file parsing began
        case "$_env_preset" in
          *"$_env_key "*) ;;
          *) export "$_env_key=$_env_value" ;;
        esac
        ;;
    esac
  done < "$EMBED_ENV_FILE"
  unset _env_key _env_value _env_k _env_preset
fi

DB_PATH=""
OUTPUT_DIR=""
MODEL_PATH="${VIBE_CODE_AUDIT_EMBED_MODEL_PATH:-$HOME/.local/share/agentroot/nomic-embed.gguf}"
MODEL_URL="${VIBE_CODE_AUDIT_EMBED_MODEL_URL:-https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q8_0.gguf}"
HOST="${VIBE_CODE_AUDIT_EMBED_HOST:-127.0.0.1}"
PORT="${VIBE_CODE_AUDIT_EMBED_PORT:-8000}"
START_LOCAL="${VIBE_CODE_AUDIT_EMBED_START_LOCAL:-1}"
if [ -z "${VIBE_CODE_AUDIT_EMBED_DOWNLOAD_MODEL:-}" ]; then
  if command -v llama-server >/dev/null 2>&1; then
    DOWNLOAD_MODEL=1
  else
    DOWNLOAD_MODEL=0
  fi
else
  DOWNLOAD_MODEL="$VIBE_CODE_AUDIT_EMBED_DOWNLOAD_MODEL"
fi
WAIT_SECONDS="${VIBE_CODE_AUDIT_EMBED_WAIT_SECONDS:-60}"
KEEP_SERVER="${VIBE_CODE_AUDIT_EMBED_KEEP_SERVER:-0}"
LLAMA_CTX_SIZE="${VIBE_CODE_AUDIT_EMBED_CTX_SIZE:-8192}"
LLAMA_BATCH_SIZE="${VIBE_CODE_AUDIT_EMBED_BATCH_SIZE:-8192}"
LLAMA_UBATCH_SIZE="${VIBE_CODE_AUDIT_EMBED_UBATCH_SIZE:-8192}"
FORCE=0

SERVER_STARTED=0
LLAMA_PID=""
LLAMA_SERVER_LOG=""
EMBED_LOG=""
EMBED_RETRY_LOG=""
UTF8_PANIC=0

while [ $# -gt 0 ]; do
  case "$1" in
    --db)
      [ $# -ge 2 ] || die "--db requires a value"
      DB_PATH="$2"
      shift 2
      ;;
    --output-dir)
      [ $# -ge 2 ] || die "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --model)
      [ $# -ge 2 ] || die "--model requires a value"
      MODEL_PATH="$2"
      shift 2
      ;;
    --host)
      [ $# -ge 2 ] || die "--host requires a value"
      HOST="$2"
      shift 2
      ;;
    --port)
      [ $# -ge 2 ] || die "--port requires a value"
      PORT="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --no-start-local)
      START_LOCAL=0
      shift
      ;;
    --download-model)
      DOWNLOAD_MODEL=1
      shift
      ;;
    --wait-seconds)
      [ $# -ge 2 ] || die "--wait-seconds requires a value"
      WAIT_SECONDS="$2"
      shift 2
      ;;
    --keep-server)
      KEEP_SERVER=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[ -n "$DB_PATH" ] || die "--db is required"
command -v agentroot >/dev/null 2>&1 || die "agentroot is not installed or not on PATH"

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$(cd "$(dirname "$DB_PATH")" && pwd)"
fi
mkdir -p "$OUTPUT_DIR"

EMBED_LOG="$OUTPUT_DIR/embed.log"
EMBED_RETRY_LOG="$OUTPUT_DIR/embed_retry.log"
LLAMA_SERVER_LOG="$OUTPUT_DIR/llama_server.log"

trap cleanup EXIT INT TERM

BACKEND="direct"
if run_embed "$EMBED_LOG"; then
  emit_result "1" "$BACKEND" "$EMBED_LOG"
  exit 0
fi

if has_pattern_in_files 'localhost:8000/v1/embeddings|/v1/embeddings|Connection refused|error sending request for url.*embeddings' "$EMBED_LOG"; then
  if health_ok; then
    BACKEND="existing-http"
    if run_embed "$EMBED_RETRY_LOG"; then
      emit_result "1" "$BACKEND" "$EMBED_RETRY_LOG"
      exit 0
    fi
  elif [ "$START_LOCAL" -eq 1 ]; then
    if start_local_server; then
      BACKEND="llama-server-local"
      if run_embed "$EMBED_RETRY_LOG"; then
        emit_result "1" "$BACKEND" "$EMBED_RETRY_LOG"
        exit 0
      fi
    else
      warn "Could not start local llama-server (this is OK — audit will use BM25-only search)"
      warn "To enable vector embeddings, install llama.cpp: brew install llama.cpp"
    fi
  fi
fi

if has_pattern_in_files 'input is too large to process' "$EMBED_LOG" "$EMBED_RETRY_LOG"; then
  warn "Embedding backend rejected batch size; prefer llama-server with larger ctx/batch settings"
fi

if has_pattern_in_files 'byte index [0-9]+ is not a char boundary|panicked at .*oversized\.rs' "$EMBED_LOG" "$EMBED_RETRY_LOG"; then
  UTF8_PANIC=1
  warn "agentroot hit UTF-8 chunking panic while embedding; continue in BM25-only mode for now"
fi

FINAL_LOG="$EMBED_LOG"
if [ -s "$EMBED_RETRY_LOG" ]; then
  FINAL_LOG="$EMBED_RETRY_LOG"
fi

emit_result "0" "$BACKEND" "$FINAL_LOG"
exit 1
