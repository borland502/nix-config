---
name: json-canvas
description: Create and edit JSON Canvas files (.canvas) with nodes, edges, groups, and connections. Use when working with .canvas files, creating visual canvases, mind maps, flowcharts, or when the user mentions Canvas files in Obsidian.
origin: kepano/obsidian-skills
---

# JSON Canvas Skill

## File Structure

A canvas file (`.canvas`) contains two top-level arrays following the [JSON Canvas Spec 1.0](https://jsoncanvas.org/spec/1.0/):

```json
{ "nodes": [], "edges": [] }
```

## Common Workflows

1. **Create**: Start with base structure → generate unique 16-char hex IDs → add nodes → add edges
2. **Add a node**: Read existing file → generate non-colliding ID → choose non-overlapping position (50-100px spacing) → append to `nodes`
3. **Connect nodes**: Generate edge ID → set `fromNode`/`toNode` → optionally set `fromSide`/`toSide` → append to `edges`
4. **Validate**: All IDs unique across nodes and edges; every `fromNode`/`toNode` references an existing node ID

## Node Types

### Text Node

```json
{ "id": "6f0ad84f44ce9c17", "type": "text", "x": 0, "y": 0, "width": 400, "height": 200,
  "text": "# Hello\n\nMarkdown content." }
```

**Pitfall**: Use `\n` for newlines in JSON strings — never literal `\\n`.

### File Node

```json
{ "id": "a1b2c3d4e5f67890", "type": "file", "x": 500, "y": 0, "width": 400, "height": 300,
  "file": "Attachments/diagram.png" }
```

### Link Node

```json
{ "id": "c3d4e5f678901234", "type": "link", "x": 1000, "y": 0, "width": 400, "height": 200,
  "url": "https://example.com" }
```

### Group Node

```json
{ "id": "d4e5f6789012345a", "type": "group", "x": -50, "y": -50, "width": 1000, "height": 600,
  "label": "Project Overview", "color": "4" }
```

## Edges

```json
{ "id": "0123456789abcdef", "fromNode": "6f0ad84f44ce9c17", "fromSide": "right",
  "toNode": "a1b2c3d4e5f67890", "toSide": "left", "toEnd": "arrow", "label": "leads to" }
```

`fromSide`/`toSide`: `top`, `right`, `bottom`, `left` | `fromEnd`/`toEnd`: `none`, `arrow`

## Colors

| Preset | Color | Preset | Color |
|--------|-------|--------|-------|
| `"1"` | Red | `"4"` | Green |
| `"2"` | Orange | `"5"` | Cyan |
| `"3"` | Yellow | `"6"` | Purple |

Or use hex: `"#FF0000"`

## Layout Guidelines

- `x` increases right, `y` increases down; position is the top-left corner
- Coordinates can be negative (canvas extends infinitely)
- Space nodes 50-100px apart; 20-50px padding inside groups
- Align to grid (multiples of 10 or 20) for cleaner layouts

## ID Generation

16-character lowercase hex strings: `"6f0ad84f44ce9c17"`

## Validation Checklist

1. All `id` values unique across both nodes and edges
2. Every `fromNode`/`toNode` references an existing node ID
3. Required fields present for each node type
4. `type` is one of: `text`, `file`, `link`, `group`
5. JSON is valid and parseable

See [references/EXAMPLES.md](references/EXAMPLES.md) for complete examples.
