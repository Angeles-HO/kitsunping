# QoS Flow MVP (Router + Kitsunping)

Status: design reference (not part of current release validation gate)

This document defines a minimal and safe path to start per-client QoS using Kitsunping state as input.

## Goal

- Prioritize one critical client (for example, the rooted phone running Kitsunping) without degrading the rest of the network.
- Keep policy understandable: client first, then group, then global defaults.
- Separate responsibility clearly:
  - decision plane: module/app + policy rules
  - action plane: router QoS implementation

## End-to-End Flow

1. Signal collection on phone
   - daemon writes runtime context into `cache/daemon.state`
   - relevant values include quality scores, transport context, and profile intent

2. Status push to router agent
   - module pushes `MODULE_STATUS` through the documented router event endpoint
   - router stores client state for policy decisioning

3. Traffic intent classification
   - minimum fields: client ID (MAC/IP), profile (`gaming|speed|stable`), priority (`high|medium|low`)
   - intent source can be `target.prop` + current daemon state

4. Router policy decision
   - sensitive/latency sessions -> high priority
   - normal or unknown sessions -> medium/low fallback
   - stale data -> safe default policy (no aggressive shaping)

5. Router policy application
   - apply queue/shaping rules per client/group
   - commit and reload router QoS service according to router platform

6. Operational validation
   - compare before/after over a meaningful period (for example 24h)
   - measure latency, p95 stability, and collateral impact on other clients

## Suggested MVP Rollout

1. Enable baseline QoS.
2. Add one high-priority queue for the critical client.
3. Add one default queue for other clients.
4. Observe and measure.
5. Expand only after stable results.

## Rollback

Always keep a router QoS backup before applying new rules.

Example rollback sequence (router-side):

1. restore previous QoS config backup
2. commit config
3. restart/reload QoS service

## Scope Boundary

This repository documents and implements client-side integration boundaries.
Router-side scripts/config generators may live in separate router-specific repositories.
