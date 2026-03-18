#!/usr/bin/env bash
# ────────────────────────────────────────────────
# Clawith — First-time Setup Script
# Sets up backend, frontend, database, and seed data.
# 当前脚本相对于项目原始脚本，移除了本机数据库检测与安装部分
# ────────────────────────────────────────────────
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ROOT="$(cd "$(dirname "$0")" && pwd)"

# Parse arguments
INSTALL_DEV=false
for arg in "$@"; do
    case $arg in
        --dev) INSTALL_DEV=true ;;
    esac
done

# --- Helper: detect server IP ---
get_server_ip() {
    # Try hostname -I (Linux), then ifconfig (macOS), then fallback
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$ip" ] && ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
    [ -z "$ip" ] && ip="<your-server-ip>"
    echo "$ip"
}

# --- Check Python version (>= 3.12 required) ---
PYTHON_BIN="${PYTHON_BIN:-python3}"
if command -v "$PYTHON_BIN" &>/dev/null; then
    PY_VER=$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
    PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
    if [ "$PY_MAJOR" -lt 3 ] || ([ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 12 ]); then
        echo -e "${RED}Python $PY_VER detected, but Clawith requires Python >= 3.12.${NC}"
        echo ""
        echo "  Please install Python 3.12+:"
        echo "    Ubuntu:     sudo apt install python3.12 python3.12-venv"
        echo "    CentOS:     sudo dnf install python3.12"
        echo "    macOS:      brew install python@3.12"
        echo "    Conda:      conda create -n clawith python=3.12"
        echo ""
        echo "  Or set PYTHON_BIN to point to a valid python3.12+ binary:"
        echo "    PYTHON_BIN=/path/to/python3.12 bash setup.sh"
        exit 1
    fi
fi

# --- Optional package mirror overrides ---
PIP_INSTALL_ARGS=()
if [ -n "${CLAWITH_PIP_INDEX_URL:-}" ]; then
    PIP_INSTALL_ARGS+=(--index-url "$CLAWITH_PIP_INDEX_URL")
fi
if [ -n "${CLAWITH_PIP_TRUSTED_HOST:-}" ]; then
    PIP_INSTALL_ARGS+=(--trusted-host "$CLAWITH_PIP_TRUSTED_HOST")
fi
NPM_MIRROR="--registry https://registry.npmmirror.com"

echo ""
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  🦞 Clawith — First-time Setup${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

# ── 1. Environment file ──────────────────────────
echo -e "${YELLOW}[1/6]${NC} Checking environment file..."
if [ ! -f "$ROOT/.env" ]; then
    cp "$ROOT/.env.example" "$ROOT/.env"
    echo -e "  ${GREEN}✓${NC} Created .env from .env.example"
    echo -e "  ${YELLOW}⚠${NC}  Please edit .env to set SECRET_KEY and JWT_SECRET_KEY before production use."
else
    echo -e "  ${GREEN}✓${NC} .env already exists"
fi

# ── 2. PostgreSQL setup ──────────────────────────
echo ""
echo -e "${YELLOW}[2/6]${NC} Setting up PostgreSQL..."

# --- Helper: find psql binary ---
find_psql() {
    # Check PATH first
    if command -v psql &>/dev/null; then
        command -v psql
        return 0
    fi
    # Search common non-standard locations
    local search_paths=(
        "/www/server/pgsql/bin"
        "/usr/local/pgsql/bin"
        "/usr/lib/postgresql/15/bin"
        "/usr/lib/postgresql/14/bin"
        "/usr/lib/postgresql/16/bin"
        "/opt/homebrew/opt/postgresql@15/bin"
        "/opt/homebrew/opt/postgresql/bin"
    )
    for dir in "${search_paths[@]}"; do
        if [ -x "$dir/psql" ]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

# --- Helper: find a free port starting from $1 ---
find_free_port() {
    local port=$1
    while ss -tlnp 2>/dev/null | grep -q ":${port} " || \
          lsof -iTCP:${port} -sTCP:LISTEN 2>/dev/null | grep -q LISTEN; do
        echo -e "  ${YELLOW}⚠${NC}  Port $port is in use, trying $((port+1))..."
        port=$((port+1))
    done
    echo "$port"
}

PG_PORT=5432
PG_MANAGED_BY_US=false

        echo -e "  ${GREEN}✓${NC} PostgreSQL is running on port 5432"
        PG_PORT=5432

        # Try to create role and database
        ROLE_EXISTS=false
        if psql -h localhost -p $PG_PORT -U "$USER" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='clawith'" 2>/dev/null | grep -q 1; then
            ROLE_EXISTS=true
            echo -e "  ${GREEN}✓${NC} Role 'clawith' already exists"
        elif sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='clawith'" 2>/dev/null | grep -q 1; then
            ROLE_EXISTS=true
            echo -e "  ${GREEN}✓${NC} Role 'clawith' already exists"
        fi

        if [ "$ROLE_EXISTS" = false ]; then
            # Try 1: as current user
            if createuser -h localhost -p $PG_PORT clawith 2>/dev/null; then
                psql -h localhost -p $PG_PORT -U "$USER" -d postgres -c "ALTER ROLE clawith WITH LOGIN PASSWORD 'clawith';" &>/dev/null
                echo -e "  ${GREEN}✓${NC} Created PostgreSQL role: clawith"
            # Try 2: via sudo -u postgres (standard Linux setup)
            elif sudo -u postgres createuser clawith 2>/dev/null && \
                 sudo -u postgres psql -c "ALTER ROLE clawith WITH LOGIN PASSWORD 'clawith';" &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Created PostgreSQL role: clawith (via sudo)"
            else
                echo -e "  ${YELLOW}⚠${NC}  Could not create role in existing PG — will init a local instance"
                PG_BIN_DIR=""  # Force local PG setup below
            fi
        fi

        if [ -n "$PG_BIN_DIR" ] || command -v psql &>/dev/null; then
            DB_EXISTS=false
            if psql -h localhost -p $PG_PORT -U "$USER" -lqt 2>/dev/null | cut -d\| -f1 | grep -qw clawith; then
                DB_EXISTS=true
            elif sudo -u postgres psql -lqt 2>/dev/null | cut -d\| -f1 | grep -qw clawith; then
                DB_EXISTS=true
            fi

            if [ "$DB_EXISTS" = true ]; then
                echo -e "  ${GREEN}✓${NC} Database 'clawith' already exists"
            else
                if createdb -h localhost -p $PG_PORT -O clawith clawith 2>/dev/null || \
                   sudo -u postgres createdb -O clawith clawith 2>/dev/null; then
                    echo -e "  ${GREEN}✓${NC} Created database: clawith"
                fi
            fi
        fi

# Ensure DATABASE_URL is correct in .env
DB_URL="${DATABASE_URL}"
if grep -q "^DATABASE_URL=" "$ROOT/.env" 2>/dev/null; then
    # Update existing DATABASE_URL
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=${DB_URL}|" "$ROOT/.env" 2>/dev/null || \
    sed -i '' "s|^DATABASE_URL=.*|DATABASE_URL=${DB_URL}|" "$ROOT/.env" 2>/dev/null
elif grep -q "^# DATABASE_URL=" "$ROOT/.env" 2>/dev/null; then
    # Uncomment and set
    sed -i "s|^# DATABASE_URL=.*|DATABASE_URL=${DB_URL}|" "$ROOT/.env" 2>/dev/null || \
    sed -i '' "s|^# DATABASE_URL=.*|DATABASE_URL=${DB_URL}|" "$ROOT/.env" 2>/dev/null
else
    echo "DATABASE_URL=${DB_URL}" >> "$ROOT/.env"
fi
echo -e "  ${GREEN}✓${NC} DATABASE_URL set (port $PG_PORT)"

# ── 3. Backend setup ─────────────────────────────
echo ""
echo -e "${YELLOW}[3/6]${NC} Setting up backend..."
cd "$ROOT/backend"

if [ ! -d ".venv" ]; then
    echo "  Creating Python virtual environment..."
    $PYTHON_BIN -m venv .venv
    echo -e "  ${GREEN}✓${NC} Virtual environment created"
fi

if [ "$INSTALL_DEV" = true ]; then
    PIP_TARGET=".[dev]"
    echo "  Installing dependencies with dev extras (this may take 2-5 minutes)..."
else
    PIP_TARGET="."
    echo "  Installing dependencies (this may take 1-2 minutes)..."
fi
if .venv/bin/pip install -e "$PIP_TARGET" "${PIP_INSTALL_ARGS[@]}" 2>&1; then
    echo -e "  ${GREEN}✓${NC} Backend dependencies installed"
else
    echo -e "  ${RED}✗${NC} Failed to install backend dependencies."
    echo "  Try manually: cd backend && .venv/bin/pip install -e '$PIP_TARGET'"
    exit 1
fi

# ── 4. Frontend setup ────────────────────────────
echo ""
echo -e "${YELLOW}[4/6]${NC} Setting up frontend..."
cd "$ROOT/frontend"

if [ ! -d "node_modules" ]; then
    if ! command -v npm &>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC}  npm not found. Skipping frontend dependency install."
        echo -e "  ${YELLOW}⚠${NC}  Install Node.js 20+ to enable frontend dev server."
        echo -e "  ${YELLOW}⚠${NC}  You can still use pre-built dist/ or Docker for frontend."
    else
        echo "  Installing npm packages..."
        npm install --silent $NPM_MIRROR 2>&1 | tail -1
        echo -e "  ${GREEN}✓${NC} Frontend dependencies installed"
    fi
else
    echo -e "  ${GREEN}✓${NC} Frontend dependencies already installed"
fi

# ── 5. Database setup ────────────────────────────
echo ""
echo -e "${YELLOW}[5/6]${NC} Setting up database..."
cd "$ROOT/backend"

# Source .env for DATABASE_URL
if [ -f "$ROOT/.env" ]; then
    set -a
    source "$ROOT/.env"
    set +a
fi

# ── 6. Seed data ─────────────────────────────────
echo ""
echo -e "${YELLOW}[6/6]${NC} Running database seed..."

if .venv/bin/python seed.py 2>&1 | while IFS= read -r line; do echo "  $line"; done; then
    echo ""
else
    echo ""
    echo -e "  ${RED}✗ Seed failed.${NC}"
    echo "  Common fixes:"
    echo "    1. Make sure PostgreSQL is running"
    echo "    2. Set DATABASE_URL in .env, e.g.:"
    echo "       DATABASE_URL=postgresql+asyncpg://clawith:clawith@localhost:5432/clawith?ssl=disable"
    echo "    3. Create the database first:"
    echo "       createdb clawith"
    echo "    4. If you see 'Ident authentication failed', configure pg_hba.conf:"
    echo "       Add this line BEFORE other host rules:"
    echo "       host  all  clawith  127.0.0.1/32  md5"
    echo "       Then reload: sudo systemctl reload postgresql"
    echo ""
    echo "  After fixing, re-run: bash setup.sh"
    exit 1
fi

# ── Summary ──────────────────────────────────────
SERVER_IP=$(get_server_ip)

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Setup complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo "  To start the application:"
echo ""
echo -e "  ${CYAN}Option A: One-command start${NC}"
echo "    bash restart.sh"
echo ""
echo -e "  ${CYAN}Option B: Manual start${NC}"
echo "    # Terminal 1 — Backend"
echo "    cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8008"
echo ""
echo "    # Terminal 2 — Frontend"
echo "    cd frontend && npx vite --host 0.0.0.0 --port 3008"
echo ""
echo -e "  ${CYAN}Option C: Docker${NC}"
echo "    docker compose up -d"
echo ""
echo -e "  ${CYAN}Access URLs:${NC}"
echo "    Local:   http://localhost:3008"
echo "    Network: http://${SERVER_IP}:3008"
echo ""
echo "  The first user to register becomes the platform admin."
echo ""
