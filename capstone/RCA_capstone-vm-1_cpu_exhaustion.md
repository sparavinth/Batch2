# Root Cause Analysis (RCA) — capstone-vm-1 CPU Exhaustion Incident

## 1. Problem Summary (3-4 sentences)
On 2026-06-19, capstone-vm-1 (Azure Ubuntu 22.04, Standard_B1s) experienced a controlled CPU exhaustion event during the FinBridge infrastructure migration capstone exercise. The fault was intentionally injected using stress-ng with one CPU worker and a 300-second timeout to validate system behavior under compute saturation. During the fault window, the single vCPU was saturated to 100%, and load average exceeded the 1.0 capacity threshold for a 1-vCPU VM, resulting in reduced responsiveness. The system recovered cleanly after stress-ng termination, with no residual memory, swap, or process integrity issues.

## 2. Timeline (use my evidence log timestamps — I will paste them below)
- **10:57:53 UTC** — `restore.sh` executed pre-fault; no `stress-ng` process found; readiness gate passed.
- **10:59:00 UTC** — `fault.sh` preflight confirmed `/tmp/restore.sh` present.
- **10:59:01 UTC** — Pre-fault baseline recorded: load `0.00 / 0.00 / 0.00`; memory `254 MB / 898 MB`; swap `0 MB`.
- **10:59:56 UTC** — Fault injection started: `stress-ng` launched (PID 2387), `--cpu 1 --timeout 300s`.
- **11:00:27 UTC (T+30s)** — Load rose to `1.03 / 0.35 / 0.13`, indicating full saturation on single vCPU.
- **11:00:58 UTC (T+60s)** — Sustained load `1.02 / 0.41 / 0.16`; no self-recovery during active stress period.
- **11:00:58 UTC** — Memory during fault: `270 MB / 898 MB`; swap remained `0 MB` (no memory pressure).
- **11:01:20 UTC** — `stress-ng` exited cleanly (83.88s observed runtime, exit code 0, 80,517 bogo ops).
- **11:03:06 UTC** — Post-fault `restore.sh` run confirmed zero `stress-ng` processes.
- **11:05:XX UTC** — Recovery validation: load `0.00 / 0.01 / 0.04`; memory `250 MB / 898 MB`; no abnormal top CPU consumers.

## 3. Root Cause (1 clear statement)
CPU exhaustion occurred because `stress-ng --cpu 1` saturated 100% of available compute on a single-vCPU Standard_B1s VM, driving load average above sustainable capacity and degrading responsiveness.

## 4. Contributing Factors (bullet list)
- Single-vCPU VM shape (Standard_B1s) provides minimal compute headroom under CPU-bound load.
- Fault configuration used a dedicated CPU worker with a long timeout (`300s`), designed to sustain pressure.
- No active CPU saturation alerting threshold was configured to trigger operational notification during the test window.
- Burstable SKU characteristics can amplify perceived responsiveness degradation when CPU demand spikes rapidly.

## 5. Fix Applied (what commands were run to remediate)
The following remediation workflow was executed on the VM to return the host to baseline:

```bash
# 1) Detect active stress process
pgrep -a stress-ng

# 2) Graceful termination
sudo pkill -15 -x stress-ng

# 3) Verify and force-stop if needed
sleep 3
pgrep -a stress-ng
sudo pkill -9 -x stress-ng

# 4) Final process validation
pgrep -x stress-ng

# 5) Run standardized restore procedure
bash ./restore.sh
```

## 6. Recovery Confirmation (what metrics confirmed recovery)
Recovery was confirmed using process, load, and memory evidence:

- **Process state:** `pgrep` returned no active `stress-ng` processes.
- **Load average:** Returned from fault-state `~1.02–1.03` to `0.00 / 0.01 / 0.04` (below 1-vCPU contention threshold).
- **CPU behavior:** Post-recovery top process CPU returned to low background levels (e.g., WALinuxAgent ~0.3%).
- **Memory stability:** Usage returned to `250 MB / 898 MB`, below pre-fault level; no leak pattern observed.
- **Swap health:** Swap remained `0 MB` throughout event and recovery.

## 7. Preventive Recommendations (at least 3 — include Azure Monitor alert rule suggestion for CPU > 80% for 5 minutes)
- Implement an Azure Monitor metric alert on VM CPU: **Percentage CPU > 80% for 5 minutes** (scope: `capstone-vm-1` or VM scale scope; severity aligned to ops paging policy).
- Add a guardrail in fault scripts to require explicit operator approval and bounded runtime before stress execution on production-like environments.
- Right-size compute for expected burst behavior: evaluate moving from Standard_B1s to Standard_B2s (or a non-burstable D-series if sustained CPU demand is expected).
- Add an automated post-fault health check stage (process, load, memory, swap) with pass/fail output persisted to incident artifacts.
- Create an operations runbook entry defining CPU saturation triage steps, kill hierarchy (SIGTERM then SIGKILL), and evidence capture commands.
