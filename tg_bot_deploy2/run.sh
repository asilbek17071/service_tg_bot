#!/usr/bin/env bash
#
# SQB Telegram Operator Bot — run script (deploy bundle).
#
#   ./run.sh          run in the foreground (Ctrl+C to stop)
#   ./run.sh bg       run in the background (nohup); PID saved to app.pid
#   ./run.sh restart  stop the background run (if any) and start it again
#   ./run.sh stop     stop a background run
#   ./run.sh status   show whether it is running
#
# Requires Java 21 on PATH (or set JAVA_HOME). No env vars are required — every setting has a
# working default baked into the jar. Override any of them by exporting its env var before running,
# e.g.  TELEGRAM_BOT_TOKEN=...  BOT_DB_PASSWORD=...  TELEGRAM_WEBHOOK_URL=...  ./run.sh
#
# Logs:  logs/app.log   (rolling, application log via logback)
#        logs/console.log (raw stdout/stderr)
#
set +e
cd "$(dirname "$0")"

JAR="tg_bot.jar"
PID_FILE="app.pid"
mkdir -p logs

# Locate a Java 21 runtime. Priority:
#   1) the JRE bundled inside this folder (./jre) -> fully self-contained, needs NO install/sudo
#   2) an explicit JAVA_HOME
#   3) java on PATH
#   4) common install locations
HERE="$(cd "$(dirname "$0")" && pwd)"
# Self-heal: if the bundled JRE is present but lost its execute bit during copy
# (scp/zip/Windows often strip +x), restore it automatically.
if [ -f "$HERE/jre/bin/java" ] && [ ! -x "$HERE/jre/bin/java" ]; then
  chmod +x "$HERE/jre/bin/"* 2>/dev/null
  chmod +x "$HERE/jre/lib/jspawnhelper" 2>/dev/null
fi
if [ -x "$HERE/jre/bin/java" ]; then
  JAVA_BIN="$HERE/jre/bin/java"
elif [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  JAVA_BIN="$JAVA_HOME/bin/java"
elif command -v java >/dev/null 2>&1; then
  JAVA_BIN="java"
else
  JAVA_BIN=""
  for d in /usr/lib/jvm/*/bin/java /opt/*/bin/java "$HOME"/.local/toolchain/*/bin/java; do
    [ -x "$d" ] && JAVA_BIN="$d" && break
  done
fi
if [ -z "$JAVA_BIN" ]; then
  echo "ERROR: Java not found (and no bundled ./jre)." >&2
  echo "Either keep the bundled jre/ folder next to this script, or set JAVA_HOME." >&2
  exit 1
fi

is_running() { [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; }

case "${1:-run}" in
  status)
    if is_running; then echo "running (PID $(cat "$PID_FILE"))"; else echo "not running"; fi
    ;;
  stop)
    if is_running; then
      kill "$(cat "$PID_FILE")" && echo "stopped (PID $(cat "$PID_FILE"))"
      rm -f "$PID_FILE"
    else
      echo "not running"
    fi
    ;;
  bg)
    if is_running; then echo "already running (PID $(cat "$PID_FILE"))"; exit 0; fi
    echo "Starting in background. Logs: logs/app.log, logs/console.log"
    nohup "$JAVA_BIN" -jar "$JAR" >> logs/console.log 2>&1 &
    echo $! > "$PID_FILE"
    echo "started (PID $(cat "$PID_FILE"))"
    ;;
  restart)
    # stop the running instance (if any), then start again in the background
    if is_running; then
      OLD_PID="$(cat "$PID_FILE")"
      echo "stopping old instance (PID $OLD_PID)..."
      kill "$OLD_PID" 2>/dev/null
      # wait up to ~15s for the old JVM to exit and release port 6061 before starting the new one
      for _ in $(seq 1 15); do kill -0 "$OLD_PID" 2>/dev/null || break; sleep 1; done
      rm -f "$PID_FILE"
    fi
    echo "Starting in background. Logs: logs/app.log, logs/console.log"
    nohup "$JAVA_BIN" -jar "$JAR" >> logs/console.log 2>&1 &
    echo $! > "$PID_FILE"
    echo "restarted (PID $(cat "$PID_FILE"))"
    ;;
  run|*)
    echo "Starting SQB Telegram Operator Bot (Ctrl+C to stop)."
    echo "App logs -> logs/app.log ; console mirrored to logs/console.log"
    "$JAVA_BIN" -jar "$JAR" 2>&1 | tee -a logs/console.log
    ;;
esac
