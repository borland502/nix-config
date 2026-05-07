---
name: obsidian-bases
description: Create and edit Obsidian Bases (.base files) with views, filters, formulas, and summaries. Use when working with .base files, creating database-like views of notes, or when the user mentions Bases, table views, card views, filters, or formulas in Obsidian.
origin: kepano/obsidian-skills
---

# Obsidian Bases Skill

## Workflow

1. Create a `.base` file in the vault with valid YAML content
2. Add `filters` to select which notes appear (by tag, folder, property, or date)
3. Add `formulas` (optional) to define computed properties
4. Configure `views` (`table`, `cards`, `list`, or `map`) with `order` specifying which properties to show
5. Validate: check YAML syntax; ensure all referenced formulas exist; verify property names

## Schema

```yaml
filters:          # Global filters — apply to all views
  and: []
  or: []
  not: []

formulas:
  total: "price * quantity"
  status_icon: 'if(done, "✅", "⏳")'

properties:
  property_name:
    displayName: "Display Name"
  formula.formula_name:
    displayName: "Formula Display Name"

summaries:
  custom_summary_name: 'values.mean().round(3)'

views:
  - type: table | cards | list | map
    name: "View Name"
    limit: 10
    groupBy:
      property: property_name
      direction: ASC | DESC
    filters:
      and: []
    order:
      - file.name
      - property_name
      - formula.formula_name
    summaries:
      property_name: Average
```

## Filter Syntax

```yaml
filters: 'status == "done"'           # Single filter

filters:
  and:
    - 'status == "done"'
    - 'priority > 3'
  or:
    - 'file.hasTag("book")'
    - 'file.hasTag("article")'
  not:
    - 'file.hasTag("archived")'
```

Operators: `==`, `!=`, `>`, `<`, `>=`, `<=`, `&&`, `||`, `!`

## Properties

Three types:
1. **Note properties** — from frontmatter: `author`, `status`
2. **File properties** — metadata: `file.name`, `file.mtime`, `file.size`, `file.tags`, `file.links`, `file.path`
3. **Formula properties** — computed: `formula.my_formula`

## Formula Syntax

```yaml
formulas:
  total: "price * quantity"
  status_icon: 'if(done, "✅", "⏳")'
  days_until_due: 'if(due_date, (date(due_date) - today()).days, "")'
  days_old: '(now() - file.ctime).days'
  created: 'file.ctime.format("YYYY-MM-DD")'
```

**Duration pitfall**: Subtracting two dates returns a `Duration`, not a number. Access a field first:

```yaml
# CORRECT
"(now() - file.ctime).days"           # get days as number
"(date(due) - today()).days.round(0)" # then apply number functions

# WRONG — Duration doesn't support .round() directly
"(now() - file.ctime).round(0)"
```

## Key Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `date()` | `date(string): date` | Parse string to date |
| `now()` | `now(): date` | Current date and time |
| `today()` | `today(): date` | Current date (time = 00:00:00) |
| `if()` | `if(cond, true, false?)` | Conditional |
| `duration()` | `duration(string): duration` | Parse duration string |

Full function reference: [references/FUNCTIONS_REFERENCE.md](references/FUNCTIONS_REFERENCE.md)

## Default Summary Formulas

`Average`, `Min`, `Max`, `Sum`, `Range`, `Median`, `Stddev`, `Earliest`, `Latest`, `Checked`, `Unchecked`, `Empty`, `Filled`, `Unique`

## YAML Quoting Rules

- Use single quotes for formulas containing double quotes: `'if(done, "Yes", "No")'`
- Use double quotes for simple strings: `"My View Name"`
- Strings containing `:`, `{`, `[`, `|`, etc. must be quoted

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `YAML syntax error` on colon in string | Quote the string: `"Status: Active"` |
| Formula crashes if property missing | Guard with `if()`: `'if(due, (date(due) - today()).days, "")'` |
| `formula.X` doesn't appear | Define `X` in `formulas` section |
| Duration arithmetic fails | Access `.days`/`.hours` first, then apply number functions |

## Embedding Bases

```markdown
![[MyBase.base]]
![[MyBase.base#View Name]]
```
