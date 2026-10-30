---
name: api-contract-parity
description: Use when comparing an API replacement with a project-approved baseline for response, filtering, count, pagination or error compatibility after explicitly installing this skill.
---

# API contract parity

Read and configure [project baseline](references/project-baseline.md). Identify
the authoritative baseline implementation/specification and replacement before
declaring a difference a defect. Do not infer service URLs, authentication,
fixtures, commands or authorization from this generic template. When live setup
is unknown, continue source comparison and offline contract fixtures.

## Compare observable contracts

Trace routing, input parsing, validation, query construction, serialization and
error mapping in both versions. Record evidence locations and expected response
types/statuses. Cover missing versus null versus empty collections, numeric
counts versus numeric strings, field presence, ordering and error envelopes.
Unknown operators and invalid parameter values must preserve baseline validation
behavior; silently dropping a filter is an observable change.

Compare count semantics with result membership. Joining children before LIMIT
can duplicate or truncate parents, even if a single page looks plausible. Check
stable sort tie breakers, page boundaries, empty final pages, offsets/cursors,
total counts, defaults and maximum page sizes. Examine AND/OR grouping, EXISTS
versus join cardinality and null semantics rather than comparing syntax alone.
Preserve documented intentional changes and clearly label unresolved intent.

## Validate with bounded fixtures

Use deterministic fixtures for zero/one/many parents, multiple children, tied
sort keys, null fields, invalid/unknown operators and parameters, authentication
and authorization failures. Capture the exact request, expected response/status,
observed response/status and count-versus-result relation. Run existing contract
tests and focused regression cases using configured tooling. Classify targets,
honor read-only scope and timeouts, and keep secrets out of evidence. Existing
authorization continues to apply; browser access does not grant mutation rights.

Source findings establish code paths, not runtime deployment identity. API tests
establish selected cases, not exhaustive compatibility. Separate confirmed
behavior, source-supported hypotheses and untested cases.

## Browser validation handoff

When the user requests browser/Claude Chrome validation, create one file-backed
handoff: environment and revision, authentication procedure without secrets,
fixture IDs, exact routes/inputs, expected types/statuses, count and pagination
checks, repeatable steps, evidence location and allowed actions. Require network
request/response evidence plus screenshots where UI behavior matters; a screenshot
alone cannot establish response types or SQL cardinality. Do not embed tokens or
claim a browser pass proves all API semantics. Mark any blocked authentication,
missing fixture or unavailable browser tool explicitly, and continue independent
source/API work. Return findings with reproducible examples and evidence paths.
