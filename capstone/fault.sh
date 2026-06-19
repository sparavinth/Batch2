#!/usr/bin/env bash
# fault.sh — Inject a CPU fault via stress-ng and monitor the impact
# Usage: bash fault.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
STRESS_DURATION=300        # seconds stress-ng runs
MONITOR_INTERVAL=30        # seconds between monitoring snapshots
RESTORE_SCRIPT="$(dirname "$(realpath "$0")")/restore.sh"

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/fault_${TIMESTAMP}.log"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_FILE}"
}

# ---------------------------------------------------------------------------
# Helper: sample CPU utilisation from /proc/stat (1-second window)
# ---------------------------------------------------------------------------
get_cpu_percent() {
    local line1 line2
    line1=$(grep '^cpu ' /proc/stat)
    sleep 1
    line2=$(grep '^cpu ' /proc/stat)

    read -r _ u1 n1 s1 i1 w1 q1 q2 <<< "$line1"
    read -r _ u2 n2 s2 i2 w2 q3 q4 <<< "$line2"

    local idle_delta=$(( (i2 + w2) - (i1 + w1) ))
    local total_delta=$(( (u2+n2+s2+i2+w2+q3+q4) - (u1+n1+s1+i1+w1+q1+q2) ))

    if [[ "$total_delta" -eq 0 ]]; then
        echo 0
    else
        echo $(( 100 - (idle_delta * 100 / total_delta) ))
    fi
}

# ---------------------------------------------------------------------------
# Helper: capture a full system snapshot (CPU%, load avg, memory)
# ---------------------------------------------------------------------------
capture_snapshot() {
    local label="$1"
    log "--- Snapshot: ${label} ---"
    log "  CPU utilisation : $(get_cpu_percent)%"
    log "  Load average    : $(cut -d' ' -f1-3 /proc/loadavg)"
    log "  Memory (free -m):"
    free -m 2>/dev/null | while IFS= read -r line; do
        log "    $line"
    done
}

# ---------------------------------------------------------------------------
# Begin fault injection
# ---------------------------------------------------------------------------
log "===== fault.sh started ====="
log "Log file: ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Step 1: Preflight — confirm restore.sh exists before proceeding
# ---------------------------------------------------------------------------
log "--- Step 1: Preflight check ---"
if [[ ! -f "$RESTORE_SCRIPT" ]]; then
    log "ERROR: restore.sh not found at '${RESTORE_SCRIPT}'. Aborting — always have a recovery path."
    exit 1
fi
log "OK: restore.sh found at ${RESTORE_SCRIPT}"

# ---------------------------------------------------------------------------
# Step 2: Pre-fault baseline
# ---------------------------------------------------------------------------
log "--- Step 2: Pre-fault baseline ---"
capture_snapshot "pre-fault"

# ---------------------------------------------------------------------------
# Step 3: Install stress-ng if not present
# ---------------------------------------------------------------------------
log "--- Step 3: Checking stress-ng installation ---"
if command -v stress-ng &>/dev/null; then
    log "OK: stress-ng already installed ($(stress-ng --version 2>&1 | head -1))"
else
    log "INFO: stress-ng not found — installing via apt-get..."
    sudo apt-get update -qq >> "${LOG_FILE}" 2>&1
    sudo apt-get install -y stress-ng >> "${LOG_FILE}" 2>&1
    log "OK: stress-ng installed ($(stress-ng --version 2>&1 | head -1))"
fi

# ---------------------------------------------------------------------------
# Step 4: Launch stress-ng — 1 CPU worker for STRESS_DURATION seconds
# ---------------------------------------------------------------------------
log "--- Step 4: Launching stress-ng (1 CPU worker, ${STRESS_DURATION}s) ---"
stress-ng --cpu 1 --timeout "${STRESS_DURATION}s" --metrics-brief >> "${LOG_FILE}" 2>&1 &
STRESS_PID=$!
log "INFO: stress-ng started with PID ${STRESS_PID}"

# ---------------------------------------------------------------------------
# Step 5: Monitor every MONITOR_INTERVAL seconds while stress-ng runs
# ---------------------------------------------------------------------------
log "--- Step 5: Monitoring (every ${MONITOR_INTERVAL}s for ${STRESS_DURATION}s) ---"
ELAPSED=0
while kill -0 "${STRESS_PID}" 2>/dev/null; do
    sleep "${MONITOR_INTERVAL}"
    ELAPSED=$(( ELAPSED + MONITOR_INTERVAL ))
    capture_snapshot "T+${ELAPSED}s"
done

# ---------------------------------------------------------------------------
# Step 6: Post-fault snapshot after stress-ng exits
# ---------------------------------------------------------------------------
log "--- Step 6: Post-fault snapshot ---"
# Allow system a moment to settle
sleep 3
capture_snapshot "post-fault"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "===== fault.sh completed ====="
log "stress-ng ran for ${STRESS_DURATION}s and has exited."
log "To restore system baseline, run: bash ${RESTORE_SCRIPT}"
log "Full log available at: ${LOG_FILE}"
