# VENT

Feedback log. Repeated/systemic workflow friction that should become future automation, docs, or workflow fixes.

## 26-08-29 16:15 — Repeated stale wakes on done/closed crew worker panes (w1J, w1N, w1P, w1Q) in one iwj delegation session

Stale wakes fire on panes that fm-teardown has just closed (or on done workers parked awaiting merge): today w1J (iwj-cron-slowdown done), w1N (iwj-cron-doc-followup done), w1P and w1Q (post-teardown). Each costs a drain+ack+reconciliation cycle with zero information gain. Prevention: the stale detector's watch cycle should consult the task's .status tail (done = terminal) before queueing a stale wake, or suppression should key on "pane missing/done" rather than idle age alone. Owner: watcher/fm-classify-lib status classification; would remove ~6 captain-visible noise events per long delegation session.
## 26-09-02 23:27 — fm-teardown herdr close-confirmation treats already-gone pane as failure

fm-teardown.sh on herdr backend cannot complete when the task pane is ALREADY gone: herdr reports "pane not found" (it closed fine externally), but teardown's close-confirmation treats that as "refused, skipped, or failed" and refuses to finish cleanup (meta/status retained forever, watcher keeps polling a dead window → recurring stale wakes). Reproduced 4x in one session (learn-hosting-multitenant-scout; pane verified gone via herdr_pane close → "not found", worktree already returned to pool by the scout itself). Fix direction: teardown should treat herdr "pane not found" as close-CONFIRMED (idempotent teardown), then proceed with durable-record cleanup.

## 26-09-21 18:17 — herdr_pane tool vs herdr 0.9.1

The `herdr_pane` tool's `run` and `send_keys` actions both fail against herdr 0.9.1 with "Expected JSON output from herdr pane run/send-keys", while the identical operations via `herdr pane run|send-keys|read` in bash succeed. Driving one pairing popup therefore cost three wasted tool calls plus manual bash fallbacks. Either parse the 0.9.1 output shape, detect the mismatch and say so, or document the bash CLI fallback in the tool description.
