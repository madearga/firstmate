---
name: handoff
description: >-
  Move in-flight work to a persistent secondmate home so it keeps running while the captain goes offline.
  Use when the captain invokes /handoff, asks to hand work off to a secondmate, or says they are going away or shutting the machine down with work still in flight.
user-invocable: true
metadata:
  internal: true
---

# handoff

Move in-flight work to a persistent secondmate home when the captain is about to go offline, so the work continues on the target host instead of dying with this session.
This skill owns the captain-facing orchestration only: what moves, where it lands, which target gaps must close first, what the captain must still decide, and what he reads when he returns.
The mechanics belong to their existing owners and are never restated here.
`secondmate-provisioning` owns target-home seeding, clone restrictions, remote-route readiness, inherited-material propagation, and the routing-registry contract.
`bin/fm-backlog-handoff.sh`'s own header owns the item-transfer command, its flags, and its durability.

## When it loads

Load on `/handoff`, on any captain request to move work to a secondmate, and whenever the captain says they are going away, going offline, or shutting down this machine with work still in flight.

## Decide what moves before moving anything

Inventory what is in flight, queued, and blocked, then classify each item.

- Work that can continue without the captain moves.
- A merge, an approval, or any other captain-owned decision stays: authority does not travel with the work.
- `local-only` work stays in the main home.
- Work the target home cannot reach - missing clone, missing registry entry, missing runtime or tooling, or a forge account that host cannot authenticate - waits until that gap is closed or is reported instead of being handed off.

State plainly what stays behind and why, because a handoff that silently strands an item is worse than no handoff.

## Sequence

1. Resolve the target from the captain's own words, or by matching the work against every registered `scope:` in `data/secondmates.md`.
2. Load `secondmate-provisioning` before touching the target home, its registry, or its clones.
3. Close the target gaps that the work actually needs: clone, registry line, runtime and tooling prerequisites, and the forge account that must be active on that host for the project's remote.
4. Move the work through the handoff helper.
5. Send one routed brief naming the work, the material it must read, the delivery mode, the boundaries it must not cross, and the fact that its reports return as marked replies.
6. Tell the captain what continues, what goes dormant, and every decision still waiting on him - before he goes offline.
7. On his return, read the accumulated marked reports and reconcile them into this home.

## Boundaries

- Merge, approval, destructive-action, and unlanded-work authority never transfer implicitly; a handed-off item may be researched, built, and proposed, but not landed without the captain's or the parent's word.
- A secondmate is idle by default, so a handoff always carries an explicit routed brief rather than expecting the mate to infer work from a new clone or a new registry line.
- Reconcile a handed-off item's state from the target home's records, never from this home's memory of what was sent.
