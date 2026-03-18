#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="$ROOT_DIR/frontend"
VENV_DIR="$ROOT_DIR/venv"
MODELS_DIR="$ROOT_DIR/backend/ml/models"

BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_HOST="${FRONTEND_HOST:-127.0.0.1}"
FRONTEND_PORT="${FRONTEND_PORT:-7777}"

BACKEND_PID=""
FRONTEND_PID=""

log() {
  printf '[pokieticker] %s\n' "$1"
}

cleanup() {
  if [ -n "${BACKEND_PID:-}" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
    kill "$BACKEND_PID" 2>/dev/null || true
  fi

  if [ -n "${FRONTEND_PID:-}" ] && kill -0 "$FRONTEND_PID" 2>/dev/null; then
    kill "$FRONTEND_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

ensure_python_env() {
  if [ ! -x "$VENV_DIR/bin/python" ]; then
    log "Creating Python virtual environment"
    python3 -m venv "$VENV_DIR"
  fi

  if ! "$VENV_DIR/bin/python" -c "import fastapi, uvicorn" >/dev/null 2>&1; then
    log "Installing backend dependencies"
    "$VENV_DIR/bin/pip" install -r "$ROOT_DIR/requirements.txt"
  fi
}

ensure_frontend_deps() {
  if [ ! -x "$FRONTEND_DIR/node_modules/.bin/vite" ]; then
    log "Installing frontend dependencies"
    (
      cd "$FRONTEND_DIR"
      npm install
    )
  fi
}

ensure_data_files() {
  if [ ! -f "$ROOT_DIR/pokieticker.db" ] && [ -f "$ROOT_DIR/pokieticker.db.gz" ]; then
    log "Unpacking database"
    gunzip -k "$ROOT_DIR/pokieticker.db.gz"
  fi

  if [ ! -d "$MODELS_DIR" ] || [ -z "$(find "$MODELS_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
    log "Unpacking ML models"
    mkdir -p "$MODELS_DIR"
    tar xzf "$ROOT_DIR/models.tar.gz" -C "$ROOT_DIR/backend/ml/"
  fi
}

start_backend() {
  log "Starting backend on http://$BACKEND_HOST:$BACKEND_PORT"
  (
    cd "$ROOT_DIR"
    exec "$VENV_DIR/bin/uvicorn" backend.api.main:app --host "$BACKEND_HOST" --port "$BACKEND_PORT"
  ) &
  BACKEND_PID=$!
}

start_frontend() {
  log "Starting frontend on http://$FRONTEND_HOST:$FRONTEND_PORT/PokieTicker/"
  (
    cd "$FRONTEND_DIR"
    exec node node_modules/vite/bin/vite.js --host "$FRONTEND_HOST" --port "$FRONTEND_PORT"
  ) &
  FRONTEND_PID=$!
}

monitor_processes() {
  while true; do
    if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
      wait "$BACKEND_PID" || true
      log "Backend exited"
      return 1
    fi

    if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
      wait "$FRONTEND_PID" || true
      log "Frontend exited"
      return 1
    fi

    sleep 1
  done
}

main() {
  require_cmd python3
  require_cmd node
  require_cmd npm
  require_cmd gunzip
  require_cmd tar

  ensure_data_files
  ensure_python_env
  ensure_frontend_deps

  log "App URL: http://$FRONTEND_HOST:$FRONTEND_PORT/PokieTicker/"
  log "Press Ctrl+C to stop both servers"

  start_backend
  start_frontend
  monitor_processes
}

main "$@"
