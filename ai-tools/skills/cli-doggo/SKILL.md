---
name: cli-doggo
description: Use when inspecting DNS records or resolver differences with doggo, including machine-readable DNS answers and choosing DNS versus mDNS, port, or HTTP checks.
---

# Inspect DNS with doggo

Use doggo for readable DNS answers or JSON results. Honor an explicitly requested
tool.

## Choose a tool

```text
What are you diagnosing?
|-- DNS record, TTL, or resolver response -> doggo
|-- LAN mDNS/DNS-SD service discovery -> avahi-browse (Linux) or dns-sd (macOS)
|-- Which local process owns a port -> lsof
|-- Reachability of a specific remote port -> a scoped port probe
`-- HTTP status or response body -> xh or curl
```

A DNS answer does not establish TCP connectivity or application health; see
[xh](../cli-xh/SKILL.md) for the HTTP step.

## Query deliberately

```sh
doggo --search=false --timeout=5s example.com A
doggo --search=false --timeout=5s --json example.com AAAA
doggo --search=false --timeout=5s example.com A @127.0.0.1:5353
```

The first two use the configured resolver; the last selects a local unicast DNS
resolver on an explicit port. Port 5353 here is an example listener, not an mDNS
discovery request.

Choose the record type explicitly. `--search=false` suppresses search-domain
expansion for an exact-name check; omit it when testing that expansion itself.
Inspect the DNS response status and answers, including NXDOMAIN or an empty
answer, rather than equating process completion with successful resolution.

Compare resolvers only when relevant to the task. Keep private names on their
intended resolver; do not send them to a public DNS service by habit.

[Upstream](https://github.com/mr-karan/doggo)
