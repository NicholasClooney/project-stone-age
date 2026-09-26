# Protocol archaeology and compatibility

Legacy compatibility has two different paths: a Godot adapter connecting to an old server, and an old client connecting to the Swift server. Choose one exact build pair and one capability before implementing either. Both are deferred beyond M000.

## Trace one action

1. Identify client encoder, transport framing, server decoder, handler, and response path.
2. Capture a controlled action in a local test environment.
3. Record bytes, boundaries, encoding, field order, endianness where applicable, escaping, checksums, and session-dependent transformations.
4. Map decoded data to a canonical command/event; keep legacy quirks inside the adapter.
5. Replay a redacted fixture and compare behavior with the reference implementation.

Do not infer packet names, opcodes, encryption, or port values from other forks. A TCP read is not a packet boundary. Test fragmented input, coalesced messages, malformed lengths, unknown messages, and invalid character encoding.

## Compatibility matrix template

| Exact client/server build | Login | Character selection | World entry | Movement | Battle | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| Not yet selected | Unknown | Unknown | Unknown | Unknown | Unknown | Pending |

Use statuses unknown, observed, implemented, and verified; include fixture IDs for verified cells. Supporting one flow does not imply support for an entire edition.

Acceptance for the first adapter: replayed login/world-entry/movement fixtures produce expected canonical state, unsupported capabilities fail explicitly, and malformed packets cannot mutate state. Keep credentials and unrelated personal data out of retained captures.
