#!/usr/bin/env bash
# restore.sh — Kill stress-ng fault injection and verify system recovery
# Usage: bash restore.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/restore_${TIMESTAMP}.log"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_FILE}"
}

# ---------------------------------------------------------------------------
# Helper: sample CPU utilisation from /proc/stat
# Returns utilisation percentage as an integer (0-100)
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
# Begin restore
# ---------------------------------------------------------------------------
log "===== restore.sh started ====="
log "Log file: ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Step 1: Check whether any stress-ng processes are running
# ---------------------------------------------------------------------------
log "--- Step 1: Checking for active stress-ng processes ---"

STRESS_PIDS=$(pgrep -x stress-ng 2>/dev/null || true)

if [[ -z "$STRESS_PIDS" ]]; then
    log "INFO: No stress-ng processes found — no active fault. Clean-run proof captured."
else
    log "INFO: Found stress-ng PIDs: ${STRESS_PIDS}"

    # -----------------------------------------------------------------------
    # Step 2: SIGTERM first
    # -----------------------------------------------------------------------
    log "--- Step 2: Sending SIGTERM to stress-ng processes ---"
    kill -TERM ${STRESS_PIDS} 2>/dev/null || true
    sleep 3

    REMAINING=$(pgrep -x stress-ng 2>/dev/null || true)
    if [[ -n "$REMAINING" ]]; then
        log "WARN: Processes still alive after SIGTERM — escalating to SIGKILL"
        kill -KILL ${REMAINING} 2>/dev/null || true
        sleep 2
    else
        log "INFO: All stress-ng processes terminated cleanly via SIGTERM"
    fi
fi

# ---------------------------------------------------------------------------
# Step 3: Confirm zero stress-ng processes remain
# ---------------------------------------------------------------------------
log "--- Step 3: Confirming zero stress-ng processes remain ---"
FINAL_CHECK=$(pgrep -x stress-ng 2>/dev/null || true)

if [[ -n "$FINAL_CHECK" ]]; then
    log "ERROR: stress-ng processes still running after kill attempts: ${FINAL_CHECK}"
    exit 1
fi
log "OK: Zero stress-ng processes confirmed"

# ---------------------------------------------------------------------------
# Step 4: Sample CPU utilisation and confirm it is below 20%
# ---------------------------------------------------------------------------
log "--- Step 4: Sampling CPU utilisation (1-second window) ---"
CPU_UTIL=$(get_cpu_percent)
log "INFO: Current CPU utilisation: ${CPU_UTIL}%"

if [[ "$CPU_UTIL" -ge 20 ]]; then
    log "WARN: CPU utilisation is ${CPU_UTIL}% — still above 20% threshold. Waiting 10s and re-sampling..."
    sleep 10
    CPU_UTIL=$(get_cpu_percent)
    log "INFO: Re-sampled CPU utilisation: ${CPU_UTIL}%"
fi

if [[ "$CPU_UTIL" -lt 20 ]]; then
    log "OK: CPU utilisation ${CPU_UTIL}% is below 20% threshold — system recovered"
else
    log "WARN: CPU utilisation ${CPU_UTIL}% remains at or above 20% after re-sample"
fi

# ---------------------------------------------------------------------------
# Step 5: Top 5 CPU consumers as recovery proof
# ---------------------------------------------------------------------------
log "--- Step 5: Top 5 CPU-consuming processes (recovery proof) ---"
TOP5=$(ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -6)
log "${TOP5}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "===== restore.sh completed successfully ====="
log "Full log available at: ${LOG_FILE}"
