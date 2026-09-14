#!/usr/bin/env bash
# Fabricサーバーの起動前セットアップ(EULA確認/永続化データのリンク/JVMオプション組み立て)を行い、
# 最後にjavaプロセスへexecする(PID1を置き換えてSIGTERMが直接javaへ届くようにするため)。
set -euo pipefail

SERVER_DIR="${SERVER_DIR:-/opt/minecraft}"
DATA_DIR="${DATA_DIR:-/data}"

log() { echo "[entrypoint] $*"; }
die() { echo "[entrypoint] ERROR: $*" >&2; exit 1; }

[[ -w "$DATA_DIR" ]] || die "$DATA_DIR is not writable by uid $(id -u). Run: sudo chown -R 1000:1000 <host data dir>"

if [[ "${EULA:-FALSE}" != "TRUE" ]]; then
  cat >&2 <<'EOF'
[entrypoint] Mojang's EULA (https://www.minecraft.net/eula) has not been accepted.
[entrypoint] Set EULA=TRUE (in .env) only if you agree to it, then restart the container.
EOF
  exit 1
fi

mkdir -p "$DATA_DIR"/world "$DATA_DIR"/mods "$DATA_DIR"/config "$DATA_DIR"/logs

echo "eula=true" > "$DATA_DIR/eula.txt"

if [[ ! -f "$DATA_DIR/server.properties" ]]; then
  log "server.properties not found in $DATA_DIR, generating default from environment variables"
  cat > "$DATA_DIR/server.properties" <<EOF
server-port=25565
motd=${MOTD:-A Fabric Minecraft Server}
difficulty=${DIFFICULTY:-normal}
gamemode=${GAMEMODE:-survival}
max-players=${MAX_PLAYERS:-20}
online-mode=${ONLINE_MODE:-true}
pvp=${PVP:-true}
view-distance=${VIEW_DISTANCE:-10}
simulation-distance=${SIMULATION_DISTANCE:-10}
white-list=${WHITELIST:-false}
enforce-whitelist=${WHITELIST:-false}
enable-rcon=${ENABLE_RCON:-false}
rcon.password=${RCON_PASSWORD:-}
rcon.port=${RCON_PORT:-25575}
level-seed=${LEVEL_SEED:-}
EOF
else
  log "server.properties already exists in $DATA_DIR, leaving it untouched"
fi

for f in ops.json whitelist.json banned-players.json banned-ips.json usercache.json; do
  [[ -f "$DATA_DIR/$f" ]] || echo "[]" > "$DATA_DIR/$f"
done

# 永続化データをサーバー作業ディレクトリへシンボリックリンクする
ln -sfn "$DATA_DIR/world" "$SERVER_DIR/world"
ln -sfn "$DATA_DIR/mods" "$SERVER_DIR/mods"
ln -sfn "$DATA_DIR/config" "$SERVER_DIR/config"
ln -sfn "$DATA_DIR/logs" "$SERVER_DIR/logs"
ln -sfn "$DATA_DIR/eula.txt" "$SERVER_DIR/eula.txt"
ln -sfn "$DATA_DIR/server.properties" "$SERVER_DIR/server.properties"
for f in ops.json whitelist.json banned-players.json banned-ips.json usercache.json; do
  ln -sfn "$DATA_DIR/$f" "$SERVER_DIR/$f"
done

MEMORY_MIN="${MEMORY_MIN:-2G}"
MEMORY_MAX="${MEMORY_MAX:-6G}"

JVM_OPTS=(
  "-Xms${MEMORY_MIN}" "-Xmx${MEMORY_MAX}"
  -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200
  -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC
  -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40
  -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20
  -XX:InitiatingHeapOccupancyPercent=15
)

if [[ -n "${JAVA_OPTS:-}" ]]; then
  read -r -a EXTRA_OPTS <<< "${JAVA_OPTS}"
  JVM_OPTS+=("${EXTRA_OPTS[@]}")
fi

log "starting Fabric server (MC ${MC_VERSION:-unknown}, Loader ${FABRIC_LOADER_VERSION:-unknown}) heap=${MEMORY_MIN}-${MEMORY_MAX}"
cd "$SERVER_DIR"
exec java "${JVM_OPTS[@]}" -jar fabric-server-launch.jar nogui "$@"
