# Router Integration Boundary

## Purpose

Kitsunping exposes a client-side integration layer for compatible router agents.
The public responsibility of this repository is the Android-side exchange only: event push, channel recommendation requests, and channel apply requests.

## Scope of This MIT Repository

This repository includes:

- The Kitsunping daemon and module runtime.
- The client-side HTTP and JSON exchange used to talk to a compatible router agent.
- Public protocol expectations documented for interoperability.

This repository does not include:

- Router-side deployment scripts.
- OpenWrt agent internals.
- Private router orchestration logic.

## Separation From Router Implementations

Compatible router agents, including KitsunpingRouter, are separate distributions.
They are not part of the MIT-licensed payload shipped in this repository and may use different license terms.

As long as the protocol contract remains compatible, router-side implementations may change independently.

## Public Integration Contract

Kitsunping currently integrates with a compatible router agent through documented endpoints such as:

- `POST /cgi-bin/router-event`
- `GET /cgi-bin/router-channel-recommend`
- `POST /cgi-bin/router-channel-apply`

Typical exchanged data includes:

- Pairing and authentication headers.
- Module status payloads.
- Channel recommendation queries.
- Channel change requests.

## Packaging Note for v6.0

The public v6.0 release can ship the main Kitsunping module and the improved application while keeping router-side implementations separate.
That means router integration can be presented as a supported feature without bundling private router code into this repository.

## Practical Rule

Keep the boundary at the protocol level:

- Kitsunping owns the client-side calls and public docs.
- Router implementations own their internal scripts and deployment model.
- Do not copy router-side private implementation files into this MIT repository.