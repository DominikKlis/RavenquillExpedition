# Guild sync: how the suite talks to guildmates

Everything goes through one scheduler in the core (`RavenquillExpedition/Comm.lua`). Modules describe their messages
(`mod:NewChannel`, `docs/module-api.md`); they never call `C_ChatInfo.SendAddonMessage` themselves.

## Limits we design for

- GUILD channel only, at most 255 bytes per message (we use 250).
- The server drops heavy senders **silently**, per player and across all addons. The only proof that a message
  went out is our own copy coming back ("echo", about a second later).
- Every guildmate's client is a sender: 40 people x every module must stay far below that limit.
- Nothing is sent inside an instance or in combat.

## The budget (per client, all modules together)

| Rule | Value |
|---|---|
| Token bucket | 3 at once, then 1 per 5 s: 12 per minute for all modules together (measured limit: 30 per minute, see below) |
| Slow mode | something lost and nothing echoed for 120 s: 1 per 5 min until an echo comes back (`RQ:CommResume()` leaves it) |
| Throttled result from the client | hold 30 s |
| Busy guild | 20 event/record messages heard from others in 60 s (max 4 per sender count): events/records wait |
| Starvation guard | an event/record that waited 30 s goes out even without a token (other addons' sends drain the bucket; they never put it below 0) |
| Other addons | their GUILD sends cost our tokens too (hook on `SendAddonMessage`) |
| Intake | per sender per minute: 15 on event/record prefixes, 15 on state prefixes; more is not read |

Measured in game (Dev test `comm.rate`, 2026-11-15): one client sending 6, 12 and 30 messages per minute for a
minute each, while another addon also sent, got every message echoed. We use 40% of the highest rate. How long the
server tolerates more, and what many clients at once do, is not measured: keep the margin. Map positions: every 5 s
while moving (user choice), at most 60 position messages per minute for the whole guild (the interval stretches with
more active senders: 40 senders, about every 40 s).

## Lanes

| Lane | For | Behaviour |
|---|---|---|
| event | things that must arrive (a highlight, a request) | queued in order (max 40, 30 min); result `delivered` / `lost` / `dropped` |
| record | data in several chunks (a gear set) | chunks one per token, whole or not at all; a newer unstarted record with the same key replaces the old one; not started in 5 min or unfinished in 10 min: dropped whole |
| state | "latest value or nothing" (a map position) | `TrySend` sends now or returns why not; lowest priority: refused while events/records wait, within 4 s of any GUILD send, after 10 in 60 s, without a token; `starving` waives the quiet rules once |

Order when a token is free: event, then the record already started, then other records. State never queues.

## Message format

- Schema channels share the prefix `RQE1`: `<tag>;<version>;<type>;<field>;<field>...` (Highlights: tag `H`).
- Existing own-prefix formats keep their bytes through raw channels: Map `RQEMap1` (state), CraftAdvisor `GCAdv1`
  (records). They move to schema channels only with a dual-format phase (receive both for two releases).
- Each module has golden fixtures (`dev/harness_compat.lua`) with the exact bytes it sends: a format change that
  isn't deliberate fails the tests.

## Versioning

- Add fields at the end: older clients ignore extra fields, newer clients see missing trailing fields as empty.
- New message types are ignored by older clients (counted as "unknown type").
- Bump the channel version only for an incompatible change; older clients then ignore those messages entirely.
- `RavenquillExpedition/dev/harness_comm.lua` runs a released 0.2.0 client next to the current one.

## Trust

- A message is about its sender unless the schema says otherwise (`from = "self"` checks every `key` field).
  Exceptions are explicit and checked in the module: Highlights accepts "witnessed loot" about a guildmate who
  doesn't run the suite, only for known guild members; CraftAdvisor relays inspected gear.
- Every field is range-checked before a handler runs; a bad message is counted, never half-applied.
- Text from the wire never keeps colour codes, separators or control characters (`RQ.Wire.Clean`).
