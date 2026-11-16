# Pruning tests after first use

Writing the test first is not optional; keeping it is. A test has done its
first job once it failed for the right reason and then passed. It stays in the
suite only if it would catch a defect that no other kept test catches.

## When and what

Prune once the task's last red-green-refactor cycle is green, before
committing. Review only tests **this change added**, whether new files or new
cases in existing files. Leave pre-existing tests alone unless your human
partner asks: deleting them is an incidental diff that a reviewer will
question.

## Cut or keep

| Cut | Keep |
|-----|------|
| Asserts existence, a constant, a default value or a type | The regression test that reproduced a fixed bug |
| Re-tests framework, language or library behavior | Boundary, error-path and failure-mode tests |
| Exercises the same path and outcome as a kept test | One test per distinct branch or outcome |
| RED-step stepping stone superseded by a stronger test | A contract other code or teams rely on |
| Debug repro, diagnostic probe or instrumentation | An integration test over a seam nothing else covers |
| Restates declarative config: a synthesized infrastructure template, a migration file, a CLI flag list | A test of logic inside that config, such as a conditional resource or a computed name |
| Asserts only on mocks | |

"Too simple to test" still does not skip the RED step; pruning decides what
stays after the test has run.

## Redundancy check when unsure

Temporarily break the production line the test drove, then run the suite with
the candidate test excluded. If a kept test fails, the candidate is redundant;
cut it. If nothing fails, it guards something unique; keep it. Restore the
line before continuing.

## Example

```typescript
// Cut: trivial — restates a constant
test('MAX_RETRIES is 3', () => expect(MAX_RETRIES).toBe(3));

// Cut: redundant — same path and outcome as the kept test below
test('eventually succeeds', async () => {
  expect(await retryOperation(failTwiceThenSucceed())).toBe('success');
});

// Keep: pins the retry count and the result
test('retries failed operations 3 times', async () => { /* ... */ });

// Keep: the error path nothing else covers
test('rethrows after the third failure', async () => { /* ... */ });
```

## Finish the prune

- Delete fixtures, helpers, imports and empty `describe` blocks that only the
  cut tests used.
- Re-run the full suite. If the project gates on coverage, run coverage too; a
  gate that fails after pruning means a kept behavior lost its test, so restore
  that one test.
- In your completion summary, list each cut test with its reason in one line.
  Tests that never reached a commit need no PR mention.
