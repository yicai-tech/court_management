#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
FRONTEND_DIR="${ROOT_DIR}/frontend"

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-court_management}"
DB_USER="${DB_USER:-court_user}"
DB_PASSWORD="${DB_PASSWORD:-}"
MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
DEPLOY_MODE="${DEPLOY_MODE:-all}"
START_BACKEND="${START_BACKEND:-0}"
BACKEND_PORT="${BACKEND_PORT:-4000}"
CLEAN_INSTALL="${CLEAN_INSTALL:-1}"
CHECK_HEALTH="${CHECK_HEALTH:-1}"
NODE_VERSION="$(node -v 2>/dev/null || true)"
NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"

usage() {
  cat <<'EOF'
Usage:
  bash deploy.sh [options]

Environment variables:
  DB_HOST=127.0.0.1
  DB_PORT=3306
  DB_NAME=court_management
  DB_USER=court_user
  DB_PASSWORD=your_password
  MYSQL_ROOT_USER=root
  MYSQL_ROOT_PASSWORD=your_root_password
  DEPLOY_MODE=all|backend|frontend
  START_BACKEND=1|0 (default 0)
  BACKEND_PORT=4000
  CLEAN_INSTALL=1|0 (default 1)
  CHECK_HEALTH=1|0 (default 1)

Examples:
  DB_PASSWORD='StrongPass123!' MYSQL_ROOT_PASSWORD='rootpass' bash deploy.sh
  DEPLOY_MODE=backend START_BACKEND=1 DB_PASSWORD='StrongPass123!' MYSQL_ROOT_PASSWORD='rootpass' bash deploy.sh
EOF
}

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERROR] Missing required command: $1"
    exit 1
  fi
}

clean_old_dependencies() {
  if [[ "${CLEAN_INSTALL}" != "1" ]]; then
    echo "[INFO] Skip cleanup (CLEAN_INSTALL=${CLEAN_INSTALL})"
    return
  fi

  echo "[INFO] Clean old dependencies..."
  rm -rf "${ROOT_DIR}/node_modules" \
         "${BACKEND_DIR}/node_modules" \
         "${FRONTEND_DIR}/node_modules"
}

check_node_version() {
  if [[ "${NODE_MAJOR}" -eq 0 ]]; then
    echo "[ERROR] Node.js is required"
    exit 1
  fi

  if [[ "${NODE_MAJOR}" -lt 16 ]]; then
    echo "[ERROR] Node.js 16 or higher is required; current version: ${NODE_VERSION}"
    exit 1
  fi

  echo "[INFO] Node.js version detected: ${NODE_VERSION}"
}

npm_install_cmd() {
  if [[ -f "$1/package-lock.json" ]]; then
    if [[ "${NODE_MAJOR}" -lt 18 ]]; then
      echo "npm ci --include=optional --legacy-peer-deps"
    else
      echo "npm ci --include=optional"
    fi
  else
    if [[ "${NODE_MAJOR}" -lt 18 ]]; then
      echo "npm install --legacy-peer-deps --include=optional"
    else
      echo "npm install --include=optional"
    fi
  fi
}

write_backend_env() {
  if [[ -f "${BACKEND_DIR}/.env" ]]; then
    echo "[INFO] backend/.env already exists, keep current file"
    return
  fi

  if [[ -z "${DB_PASSWORD}" ]]; then
    echo "[ERROR] DB_PASSWORD is required when backend/.env does not exist"
    exit 1
  fi

  cat > "${BACKEND_DIR}/.env" <<EOF
DB_TYPE=mysql
MONGO_URI=mongodb://localhost:27017/court_management
MYSQL_HOST=${DB_HOST}
MYSQL_PORT=${DB_PORT}
MYSQL_DATABASE=${DB_NAME}
MYSQL_USER=${DB_USER}
MYSQL_PASSWORD=${DB_PASSWORD}
JWT_SECRET=change-this-secret
WECHAT_APPID=
WECHAT_SECRET=
EOF
  echo "[INFO] Created backend/.env"
}

prepare_database() {
  if [[ -z "${MYSQL_ROOT_PASSWORD}" ]]; then
    echo "[ERROR] MYSQL_ROOT_PASSWORD is required for database initialization"
    exit 1
  fi

  echo "[1/5] Create database and grant privileges..."
  mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME}
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL

  echo "[2/5] Import coach schema..."
  mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${DB_NAME}" < "${BACKEND_DIR}/sql/coach_schema_mysql.sql"
}

install_backend() {
  echo "[3/5] Install backend dependencies..."
  local cmd
  cmd="$(npm_install_cmd "${BACKEND_DIR}")"
  (cd "${BACKEND_DIR}" && eval "${cmd}")

  echo "[4/5] Sync backend tables via Sequelize..."
  (cd "${BACKEND_DIR}" && npm run db:sync)
}

install_workspace_root() {
  echo "[INFO] Install root workspace dependencies..."
  local cmd
  cmd="$(npm_install_cmd "${ROOT_DIR}")"
  (cd "${ROOT_DIR}" && eval "${cmd}")
}

build_frontend() {
  echo "[5/5] Install and build frontend..."
  local cmd
  cmd="$(npm_install_cmd "${FRONTEND_DIR}")"
  (cd "${FRONTEND_DIR}" && eval "${cmd}" && npm run build)
}

stop_existing_backend() {
  if [[ -f "${BACKEND_DIR}/backend.pid" ]]; then
    local old_pid
    old_pid="$(cat "${BACKEND_DIR}/backend.pid" 2>/dev/null || true)"
    if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" >/dev/null 2>&1; then
      echo "[INFO] Stop existing backend process PID=${old_pid}"
      kill "${old_pid}" || true
    fi
    rm -f "${BACKEND_DIR}/backend.pid"
  fi
}

start_backend() {
  if [[ "${START_BACKEND}" != "1" ]]; then
    return
  fi

  stop_existing_backend

  echo "[INFO] Starting backend in background..."
  nohup bash -lc "cd '${BACKEND_DIR}' && npm run start" > "${BACKEND_DIR}/backend.out.log" 2> "${BACKEND_DIR}/backend.err.log" &
  echo $! > "${BACKEND_DIR}/backend.pid"
  echo "[INFO] Backend PID saved to ${BACKEND_DIR}/backend.pid"
}

check_health() {
  if [[ "${START_BACKEND}" != "1" || "${CHECK_HEALTH}" != "1" ]]; then
    return
  fi

  ensure_command curl
  echo "[INFO] Health check: http://127.0.0.1:${BACKEND_PORT}/api/health"
  for _ in $(seq 1 20); do
    if curl -fsS "http://127.0.0.1:${BACKEND_PORT}/api/health" >/dev/null 2>&1; then
      echo "[INFO] Backend health check passed"
      return
    fi
    sleep 1
  done

  echo "[WARN] Backend did not become healthy in time. Check logs:"
  echo "       ${BACKEND_DIR}/backend.out.log"
  echo "       ${BACKEND_DIR}/backend.err.log"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  ensure_command mysql
  ensure_command npm
  check_node_version
  clean_old_dependencies

  if [[ ! -d "${BACKEND_DIR}" ]]; then
    echo "[ERROR] backend directory not found: ${BACKEND_DIR}"
    exit 1
  fi

  if [[ "${DEPLOY_MODE}" == "all" || "${DEPLOY_MODE}" == "backend" ]]; then
    write_backend_env
    prepare_database
    install_backend
  fi

  if [[ "${DEPLOY_MODE}" == "all" || "${DEPLOY_MODE}" == "frontend" ]]; then
    install_workspace_root
    build_frontend
  fi

  start_backend
  check_health

  echo "Done."
  echo "Backend: ${BACKEND_DIR}"
  echo "Frontend: ${FRONTEND_DIR}/dist"
}

main "$@"