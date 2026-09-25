# VENT

Feedback log. Repeated/systemic workflow friction that should become future automation, docs, or workflow fixes.

## 26-08-29 16:15 — Repeated stale wakes on done/closed crew worker panes (w1J, w1N, w1P, w1Q) in one iwj delegation session

Stale wakes fire on panes that fm-teardown has just closed (or on done workers parked awaiting merge): today w1J (iwj-cron-slowdown done), w1N (iwj-cron-doc-followup done), w1P and w1Q (post-teardown). Each costs a drain+ack+reconciliation cycle with zero information gain. Prevention: the stale detector's watch cycle should consult the task's .status tail (done = terminal) before queueing a stale wake, or suppression should key on "pane missing/done" rather than idle age alone. Owner: watcher/fm-classify-lib status classification; would remove ~6 captain-visible noise events per long delegation session.
## 26-09-02 23:27 — fm-teardown herdr close-confirmation treats already-gone pane as failure

fm-teardown.sh on herdr backend cannot complete when the task pane is ALREADY gone: herdr reports "pane not found" (it closed fine externally), but teardown's close-confirmation treats that as "refused, skipped, or failed" and refuses to finish cleanup (meta/status retained forever, watcher keeps polling a dead window → recurring stale wakes). Reproduced 4x in one session (learn-hosting-multitenant-scout; pane verified gone via herdr_pane close → "not found", worktree already returned to pool by the scout itself). Fix direction: teardown should treat herdr "pane not found" as close-CONFIRMED (idempotent teardown), then proceed with durable-record cleanup.

## 26-09-21 18:17 — herdr_pane tool vs herdr 0.9.1

The `herdr_pane` tool's `run` and `send_keys` actions both fail against herdr 0.9.1 with "Expected JSON output from herdr pane run/send-keys", while the identical operations via `herdr pane run|send-keys|read` in bash succeed. Driving one pairing popup therefore cost three wasted tool calls plus manual bash fallbacks. Either parse the 0.9.1 output shape, detect the mismatch and say so, or document the bash CLI fallback in the tool description.
## 26-09-25 23:48 — fm-guard false WATCHER DOWN after timezone change

The Pi turn-end guard and bin/fm-guard.sh reported "WATCHER DOWN - no live watcher holds this home lock" on every turn for several turns while the watcher was provably alive: fresh 5-14s beacon, a 4-day-old watcher chain, and a live lock owner. Each turn forced the prescribed repair call plus a manual drain, and fm_watch_arm_pi always answered "unchanged - Pi extension already owns an arm child", so the sanctioned repair path could not clear it. Root cause: on macOS fm_pid_identity falls back to `ps -o lstart= -o command=`, whose rendered local time shifted by one hour when the machine's timezone changed WITA->WIB, so the stored lock identity stopped matching the live process and the verdict degraded to the misleading "no-watcher" reason. Fix direction: make the macOS identity clock/timezone-immune (epoch start time or process birth time, as Linux already does via /proc stat field 22), and give the identity mismatch its own reported reason instead of "no live watcher process holds this home lock", which sent me hunting a dead watcher that had been healthy the whole time.
