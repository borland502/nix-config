---
name: react18-batching-patterns
description: Diagnose and fix automatic batching regressions in React 18 class components. Use when a class component has multiple setState calls in an async method, setTimeout, Promise .then()/.catch(), or native event handler. Use before writing any flushSync call — the decision tree prevents unnecessary overuse.
origin: github/awesome-copilot
---

# React 18 Automatic Batching Patterns

Reference for diagnosing and fixing the most dangerous silent breaking change in React 18 for class-component codebases.

## The Core Change

| Location of setState | React 17 | React 18 |
|---|---|---|
| React event handler | Batched | Batched (same) |
| `setTimeout` | Immediate re-render | **Batched** |
| `Promise .then()` / `.catch()` | Immediate re-render | **Batched** |
| `async/await` | Immediate re-render | **Batched** |
| Native `addEventListener` callback | Immediate re-render | **Batched** |

**Batched** = all `setState` calls in that execution context flush together in a single re-render. No intermediate renders occur.

## Quick Diagnosis

Read every async class method. Ask: does any code after an `await` read `this.state` to make a decision?

```
Code reads this.state after await?
  YES → Category A (silent state-read bug) — refactor, no flushSync
  NO, but intermediate render must be visible to user?
    YES → Category C (flushSync needed)
    NO → Category B (refactor, no flushSync)
```

## Category A — Silent State-Read Bug

```javascript
// BROKEN in React 18: this.state may not reflect setState above
async handleSubmit() {
  this.setState({ loading: true });
  await this.props.onSubmit(this.state.data); // state.loading may still be false here
  if (this.state.error) { ... }               // reading stale state
}

// FIX: Pass data directly, don't read this.state after await
async handleSubmit() {
  const { data } = this.state;  // capture before await
  this.setState({ loading: true });
  await this.props.onSubmit(data);
  // don't read this.state here — use local variables
}
```

## Category B — Unnecessary Intermediate State

```javascript
// BROKEN: intermediate setState for loading spinner doesn't render
async fetchData() {
  this.setState({ loading: true });
  const data = await api.fetch();
  this.setState({ loading: false, data });
}

// FIX: Refactor — keep loading: true until data arrives
// If intermediate render isn't user-visible, no flushSync needed
```

## Category C — User Must See Intermediate State

```javascript
import { flushSync } from "react-dom";

async handleSubmit() {
  // Force spinner to render before the async operation starts
  flushSync(() => { this.setState({ submitting: true }); });
  await this.props.onSubmit(this.state.data);
  this.setState({ submitting: false });
}
```

## The flushSync Rule

**Use `flushSync` sparingly.** It forces a synchronous re-render, bypassing React 18's concurrent scheduler. Overusing it negates React 18 performance benefits.

Only use `flushSync` when:
- The user **must** see an intermediate UI state before an async operation begins
- A spinner/loading state must render before a fetch starts
- Sequential UI steps have distinct visible states (progress wizard, multi-step flow)

In most cases the fix is a **refactor** — restructuring code to not read `this.state` after `await`.

## Detecting Affected Code

Scan for multiple `setState` calls in async contexts:

```bash
# Find async methods with multiple setState calls
rg -n 'async\s+\w+.*\{' --include="*.js" --include="*.jsx" -l
rg -n 'setState.*\n.*await|await.*\n.*setState' --include="*.jsx" -l
```

Look for: `setTimeout(() => { this.setState...`, `promise.then(() => { this.setState...`, `async method() { ... setState ... await ...`.

## Test Failures After React 18 Upgrade

If tests assert intermediate state between two `setState` calls, they'll fail because batching now prevents intermediate renders:

```javascript
// Test that expected intermediate state — now breaks
act(() => { component.handleClick(); });
expect(component.state.loading).toBe(true); // may now be false (batched)
```

Fix: wrap in `act` with `flushSync` if the intermediate state must be observable, or remove the intermediate assertion and test the final state only.
