---
name: cli-jless
description: Use when interactively exploring unfamiliar JSON or YAML in a terminal, or choosing between jless, jq, yq, gron, and dasel for structured data.
---

# Browse JSON and YAML with jless

Use jless to explore nested responses without printing the whole document into an
agent transcript. Honor an explicitly requested tool.

## Choose a tool

```text
Need structured data?
|-- Interactive, collapsible JSON/YAML viewer -> jless
|-- Exact JSON fields, filtering, aggregation, or automation -> jq
|-- YAML-specific queries or edits -> yq (Mike Farah's Go version here)
|-- Shared queries/updates or conversion across formats -> dasel
|-- Discover unknown JSON key paths with text search -> gron, then rg
`-- Literal text search without parsing -> rg
```

For cross-format examples, see [dasel](../cli-dasel/SKILL.md).
jless is a viewer; use a parser to produce machine-readable output.

## Use

```sh
jless response.json
jless config.yaml
jless --yaml < config.yaml
```

Use `j`/`k` to move, `h`/`l` to collapse/expand, `/` to search, `F1`
for help, and `q` to quit. YAML comments and anchors are not presented as source;
inspect the original file when those matter.

An agent without an interactive terminal should select a bounded result with
`jq`, `yq`, or `dasel`. Do not launch a pager and wait for unavailable input.

[Upstream](https://github.com/PaulJuliusMartinez/jless)
