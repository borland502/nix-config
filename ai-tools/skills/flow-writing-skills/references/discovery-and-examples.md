# Discovery and examples

Use this reference when tuning descriptions, organizing resources or selecting
examples. The entry retains the essential authoring and validation gates.

## Descriptions drive selection

The name and description are visible before the body. Describe concrete triggers
and symptoms in third person, preferably “Use when”. Include terminology another
agent would search: error signatures, tools and meaningful synonyms. Do not put
the workflow in the description: it can become a shortcut that bypasses the
body's actual gates. Avoid generic keyword catchalls and first-person copy.

```yaml
name: diagnosing-query-cardinality
description: Use when a SQL rewrite changes entity counts, membership or pagination.
```

Use lowercase letters, digits and hyphens for names, under 64 characters. Match
the folder name. Preserve supported existing metadata when editing. Required
frontmatter is `name` and `description`; keep descriptions below 1,024 characters
and preferably below 500. The entry should help an agent decide what to load.

## Separate invariant from conditional detail

Keep shared purpose, essential constraints and reference routing in `SKILL.md`.
Put substantial mode-specific schemas, recipes and examples in named references;
describe the condition for reading each. Do not replace a giant entry with one
giant reference that must always be loaded. Small self-contained skills need no
extra router. Scripts are appropriate for repeated deterministic mechanics;
assets are appropriate for files copied into deliverables.

Link resources relatively and verify their destinations after moving files.
Refer to another required skill by name and make the requirement explicit;
do not use `@` force-loading to import entire resources into every invocation.
Avoid duplicating canonical instructions across entries and references.

Use the existing skill-creator initializer only when it helps create a new
skill; never reinitialize an existing one. Do not add unrelated README files,
changelogs or unused scaffold directories. Project-only skills belong in the
project's chosen harness directory after explicit installation, outside global
discovery. Do not silently change an existing invocation policy.

## Examples and diagrams

One complete, relevant example is better than versions in several languages.
Choose the language used by the task; document why the non-obvious step matters.
Keep sample data generic and public-safe. Avoid session narratives or brittle
private layouts presented as universal defaults.

Use tables for reference mappings and ordinary numbered lists for linear steps.
A small flowchart can clarify a non-obvious decision or loop; keep code out of
graph labels. Existing diagram conventions are in
[graphviz conventions](../graphviz-conventions.dot), and the local
`render-graphs.js` supports separate or combined SVG output when needed.

## Verify discovery and retrieval

Test realistic requests that should select the skill and counterexamples that
should not. Have the evaluator retrieve the correct conditional reference rather
than loading every file. Validate the frontmatter with the skill-creator's
bundled validator and run repository budget/reference checks. Entry bytes are a
context inventory measure, not a promise of billed-token savings.
