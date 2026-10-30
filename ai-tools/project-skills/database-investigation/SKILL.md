---
name: database-investigation
description: Use when investigating SQL query behavior, counts, joins, filters or execution plans in a project that has explicitly installed and configured this skill.
---

# Database investigation

Establish the intended row population before comparing performance. Read and
configure [project baseline](references/project-baseline.md) first. This template
does not infer a database, connection tool, schema, authorization or environment.
If configuration is missing, inspect source and build an offline fixture while
identifying the missing live prerequisite; do not guess or request credentials
that the project's documented credential workflow can supply.

## Establish the contract

Capture the complete before/after queries, bound parameter types, schema keys,
nullability, constraints, intended entity being counted and relevant tests.
Distinguish SQL evidence from assumptions about an ORM or query builder. Trace
filters, grouping, ordering, pagination and count queries through their callers.

Compare entity ID sets and per-ID multiplicities before comparing totals.
`COUNT(*)` counts joined rows; `COUNT(DISTINCT parent.id)` counts distinct
non-null parents. Replacing EXISTS with a join can change both cardinality and
membership. Review inner/outer joins, predicate placement, null versus empty
values, duplicate children, missing children and AND/OR grouping. Check whether
limiting joined rows changes the parent page or disagrees with the count.

## Safe measurements

Classify the actual target before any live operation. Unknown, production,
shared or unregenerable targets keep the conservative authorization boundary.
Existing authorization persists within its stated scope. Prefer a disposable
local fixture for reproduction. Non-production probes still need the project's
guardrails and named cleanup before creating anything.

Use the configured read-only connection, transaction mode, statement timeout,
lock timeout and result limits. A SELECT can invoke volatile functions or a
write CTE; inspect the entire statement. Do not run writes or assume rollback
makes execution safe. `EXPLAIN ANALYZE` executes the statement. Begin with
non-executing EXPLAIN where authorized; execution measurements require safe
statements, an appropriate target and explicit scope. Do not run a large
unbounded query just to obtain a count.

## Reproduce and deliver

Build a minimal fixture with zero, one and multiple matching children per
parent; include nulls, duplicate join paths, filter boundary combinations and
stable pagination ties. State expected parent IDs and multiplicities before
running each version. Compare actual IDs, counts, errors and plans. Restore
intended semantics before claiming a faster replacement is compatible.

Save queries, redacted schema assumptions, fixture definitions, commands,
tool/version and target classification in a named artifact outside tracked
product files unless requested. Report expected versus observed results with
evidence paths, measured versus inferred conclusions, timeout/resource limits
and untested cases. Do not publish connection strings or secret parameter data.
