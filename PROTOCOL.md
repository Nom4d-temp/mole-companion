# Mole Companion protocol v1

This protocol is implemented by optional companion support in Mole 1.6.0+. Use Rednet protocol `mole-companion/1`. All messages are plain tables, version `v=1`. Never evaluate received Lua or shell commands. This protocol is for trusted networks, not adversarial authentication.

## Pairing

The station displays its computer ID and a six-digit code for 300 seconds. The `mole pair <station ID> <code>` command must check that the turtle has a wireless modem (`isWireless()` true), open it, and send directly to that station:

```lua
{v=1,kind="pair_hello",code="123456",name="North",wireless=true}
```

The station asks for local confirmation and a friendly name before saving the actual Rednet sender ID. It replies to that ID:

```lua
{v=1,kind="paired",code="123456",station=7,token="opaque pairing token"}
```

The turtle must accept this only from the station it is actively pairing with and for its current code, persist the station ID/token, then send the readiness confirmation below. Status reports begin when Mole starts or resumes a job. Replies may be retried for 30 seconds; duplicate replies must not reset a running mining job. Re-pairing is explicit and rotates the token. A station restart loads pairings but marks all turtles as not recently heard until they report again.

After saving the pairing, Mole sends `{v=1,kind="pair_ready",token=token,code=code}` directly to the station. The station validates the paired sender/token and replies `{v=1,kind="pair_verified",token=token,code=code}`. The turtle retries readiness every three seconds for up to 15 seconds. This marks the station as paired and waiting for Mole without inventing position or job data. Missing final confirmation retains pairing and directs the user to check the connection.

A local connection check uses `{v=1,kind="ping",token=token,nonce=nonce}` and an authenticated-by-pairing-token `{v=1,kind="pong",token=token,nonce=nonce}` response. As with all v1 traffic, the token is not cryptographic protection against other players.

## Reports

Send to the paired station only. Every report includes:

- `v=1`, `kind`, `token`.
- `session`: a new unique string for each turtle-side process/boot, at most 48 characters. This is a transport session, not a mining job ID.
- `seq`: a positive increasing integer **per message kind** within that session.

A new session starts with a status message. Send a status heartbeat approximately every five seconds and on important state transitions; do not block mining waiting for delivery. The station considers contact stale after 15 seconds. Session changes allow counters to restart; retired sessions cannot become current again. After 32 retired sessions during one station process, re-pairing refreshes the connection.

Status:

```lua
{v=1,kind="status",token=token,session=session,seq=1,
 job="stable-quarry-id",phase="Mining",y=18,depth=46,right=3,forward=7,fuel=1450,inventory=9,
 uncertain=false,detail="Optional next action",progress="15/100 tunnel positions"}
```

`job` is a stable nonempty ID for the saved quarry (max 64 characters), preserved across turtle restarts and changed for a new quarry. A new job clears previous discoveries on the station. All position fields are finite numbers, even when marked uncertain. Y means estimated world Y; depth/right/forward are relative to the job's start. Fuel is a nonnegative number or `"unlimited"`. Phase is a readable string, max 32 characters. Detail/progress are bounded to 160/64 characters. Recovery must set `uncertain=true` when its physical pose is not confirmed. Emergency ascent should clearly identify its own coordinate frame in detail; do not present its temporary horizontal anchor as confirmed quarry displacement.

Activity log:

```lua
{v=1,kind="log",token=token,session=session,seq=1,text="Returning to unload."}
```

Messages are bounded to 256 characters. Split longer Mole output into ordered messages. On reconnect, replay up to 80 recent lines or send a current summary. Rednet is not a guaranteed delivery stream; log sequence gaps can occur. Do not block mining to retransmit every log.

Unfamiliar block:

```lua
{v=1,kind="discovery",token=token,session=session,seq=1,
 job="stable-quarry-id",block="examplemod:tin_ore",name="Tin ore",count=8}
```

`count` is a positive integer **snapshot total** for that ID, not an increment. Announce after successful mining, not merely inspection. Define unfamiliar blocks on the turtle as mined blocks outside its recognised vanilla ore list and configured trash list, without altering what it mines. Readable name is optional. Resend discovery snapshots after station reconnect; retain job totals on the turtle if desired. The station keeps 128 unique IDs. Activity logs announce unfamiliar IDs before digging; discovery snapshots do not duplicate those entries. Discovery packets must include the current status `job`; late discoveries from a previous job are ignored.

## Safe return requests

Station to turtle:

```lua
{v=1,kind="command",action="return",token=token,request="unique request ID",session=session}
```

Accept only the paired station sender/token, the current turtle session, and `action="return"`. No arbitrary commands. Persist the accepted request before acknowledging and apply it at a safe checkpoint after any in-flight move/turn is settled. Do not run another Mole process. Recovery or emergency escape retains control when normal return is unavailable; explicitly reject or report deferred handling. The current station handles accepted/completed/rejected acknowledgements, not a separate deferred result.

Turtle to station:

```lua
{v=1,kind="ack",token=token,session=session,seq=1,
 request="unique request ID",result="accepted",detail="Optional explanation"}
```

Results: `accepted`, `completed` (home and paused), or `rejected`. Repeated request IDs must be idempotent and re-acknowledged, including across reboot where persisted. The station sends immediately, retries at 3/6/9 seconds, and stops retrying at 12 seconds if no acknowledgement arrives. It labels the request unconfirmed and permits an explicit retry. Accepted requests are not periodically reissued; status remains the source of progress if a completion acknowledgement is lost.

## Optionality requirements for Mole

Network support must be disabled unless explicitly paired/enabled. No modem, detached modem, missing station, malformed packets, full queues, or send/receive errors may affect movement, refueling, recovery, or job state. Use bounded outgoing queues and isolate listener errors. Network callbacks only set flags; the main mining loop owns physical actions and checkpoint writes. Ctrl+T termination remains local, and reports resume only when Mole runs. Standalone Mole must still pass its complete regression suite without network globals.

Optional status field inventory is the number of occupied turtle slots, an integer from 0 to 16. Older senders may omit it.
