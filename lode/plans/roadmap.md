# Current roadmap

The current work focuses on reliable sessions with more than three players and
clear host-side diagnostics.

```mermaid
flowchart TD
    Capacity[Capacity override] --> Invites[Steam invitations]
    Invites --> UI[Party UI visibility]
    UI --> Stability[Four-player stability]
    Stability --> Release[Nexus Mods release]
```

## Active work

- Identify the party widgets that hide at three players.
- Keep `+Party Member` and `Code` available while capacity remains.
- Record enough network data to diagnose client actor-channel failures.
- Test four-player world travel and replication.

## Deferred work

- Add distribution targets for other mod hosting websites.
- Decide whether party UI changes must remain host-only.

## Validation example

```text
[MorePlayers] Party UI snapshot begin reason=AddPlayerState
```

Related: [Party UI](../runtime/party-ui.md), [Session capacity](../runtime/session-capacity.md), and [Distribution](../distribution/summary.md).
