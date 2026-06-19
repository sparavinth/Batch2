# Ops Handover — capstone-vm-1 CPU Exhaustion Incident

## Handover Metadata
- **Project:** FinBridge infrastructure migration capstone
- **Incident Title:** CPU exhaustion on `capstone-vm-1` during controlled stress test
- **Date (UTC):** 2026-06-19
- **Environment:** Azure VM, Ubuntu 22.04 LTS, Standard_B1s (1 vCPU, ~1 GB RAM)
- **Current Status:** Resolved; system returned to baseline
- **Handover From:** SRE / Fault Injection Operator
- **Handover To:** Receiving Ops Team

## 1. Problem Summary (3-4 sentences)
On 2026-06-19, `capstone-vm-1` experienced a controlled CPU exhaustion event during the FinBridge migration capstone exercise. The event was intentionally induced using `stress-ng` with one CPU worker and a 300-second timeout to validate behavior under compute saturation. During the fault window, the single vCPU was saturated to 100%, causing the load average to exceed the 1.0 threshold for a 1-vCPU host and reducing system responsiveness. The fault process exited cleanly and post-fault recovery checks confirmed no residual process, memory, or swap issues.

## 2. Timeline
- **10:57:53 UTC** — `restore.sh` pre-check run; no active `stress-ng` process; readiness gate passed.
- **10:59:00 UTC** — `fault.sh` preflight confirmed recovery script availability.
- **10:59:01 UTC** — Baseline captured: load `0.00 / 0.00 / 0.00`, memory `254 MB / 898 MB`, swap `0 MB`.
- **10:59:56 UTC** — Fault started: `stress-ng` launched (PID 2387), `--cpu 1 --timeout 300s`.
- **11:00:27 UTC** — T+30s: load `1.03 / 0.35 / 0.13` (single-vCPU saturation).
- **11:00:58 UTC** — T+60s: load `1.02 / 0.41 / 0.16` (sustained contention), memory `270 MB / 898 MB`, swap `0 MB`.
- **11:01:20 UTC** — `stress-ng` exited cleanly (runtime ~83.88s, exit code `0`).
- **11:03:06 UTC** — `restore.sh` post-fault run confirmed zero `stress-ng` processes.
- **11:05:XX UTC** — Recovery validated: load `0.00 / 0.01 / 0.04`, memory `250 MB / 898 MB`, no abnormal top CPU consumers.

## 3. Root Cause
CPU exhaustion was caused by `stress-ng --cpu 1` saturating 100% of compute on a single-vCPU Standard_B1s VM, driving load average above the host’s practical capacity and degrading responsiveness.

## 4. Contributing Factors
- Single-vCPU instance (`Standard_B1s`) has limited tolerance to CPU-bound workloads.
- Fault profile used sustained CPU pressure (`--cpu 1 --timeout 300s`).
- No active CPU alert policy was configured to trigger operational response thresholds.
- Burstable VM behavior can worsen user-perceived latency during sudden CPU spikes.

## 5. Fix Applied
The following remediation commands were run on the VM:

```bash
# Detect active stress process
pgrep -a stress-ng

# Graceful termination
sudo pkill -15 -x stress-ng

# Re-check and force terminate if needed
sleep 3
pgrep -a stress-ng
sudo pkill -9 -x stress-ng

# Final process validation
pgrep -x stress-ng

# Standardized recovery script
bash ./restore.sh
```

## 6. Recovery Confirmation
Recovery was confirmed through these checks:

- **Process:** `pgrep` showed no active `stress-ng` process.
- **Load:** Reduced from `~1.02–1.03` during fault to `0.00 / 0.01 / 0.04` after remediation.
- **CPU:** Top CPU consumers returned to low background utilization (example: `WALinuxAgent ~0.3%`).
- **Memory:** Stable and improved from fault-state to `250 MB / 898 MB` post-recovery.
- **Swap:** Remained `0 MB` throughout event and recovery.

## 7. Preventive Recommendations
- Configure Azure Monitor alert: **Metric = Percentage CPU, Condition = > 80%, Aggregation window = 5 minutes, Scope = capstone-vm-1, Action Group = Ops on-call notification**.
- Add script-level safety controls for fault tests: explicit operator confirmation, hard runtime cap, and mandatory rollback path verification.
- Right-size compute for expected burst load: evaluate move from `Standard_B1s` to `Standard_B2s`; use D-series if sustained non-burst CPU demand is expected.
- Add automated post-fault health gate (process, load, memory, swap) and archive results as incident evidence.
- Publish a CPU saturation runbook for Ops including triage commands, termination sequence, and escalation criteria.

## Ownership and Escalation
- **Primary Owner:** SRE / Platform Operations
- **Secondary Owner:** Cloud Infrastructure Engineer
- **Escalation L1:** Ops On-Call
- **Escalation L2:** Platform Lead
- **Escalation L3:** Cloud Architect
- **Escalation Trigger:** CPU > 80% for 5 minutes, recurring load > 1.0 on B1s, or service responsiveness degradation.

## Severity and Impact Matrix
| Dimension | Value |
|---|---|
| Severity | SEV-3 (controlled test impact, no customer-facing outage) |
| Blast Radius | Single VM (`capstone-vm-1`) |
| User Impact | Degraded responsiveness during fault window |
| Data Integrity | No impact observed |
| Duration | 10:59:56 to 11:01:20 UTC |
| Residual Risk | Low after remediation; medium if capacity/alerting remains unchanged |

## Action Tracker
| Action | Owner | Priority | Due Date (UTC) | Status |
|---|---|---|---|---|
| Create Azure Monitor CPU alert (>80% for 5 min) + Action Group routing | Cloud Infrastructure Engineer | P1 | 2026-06-22 | Open |
| Add fault-script guardrails (approval + max runtime + rollback check) | SRE | P1 | 2026-06-24 | Open |
| Evaluate and execute VM resize recommendation (`B1s` -> `B2s`) | Platform Operations | P2 | 2026-06-26 | Open |
| Add automated post-fault verification artifact export | SRE | P2 | 2026-06-27 | Open |
| Update Ops runbook with CPU saturation triage and escalation flow | Ops Team Lead | P2 | 2026-06-30 | Open |
