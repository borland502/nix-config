# Ticket Analysis & Update Templates

## Analyzing a Ticket

When retrieving a ticket for development or test automation, extract:

### 1. Testable Requirements

- **Functional requirements** — What the feature does
- **Acceptance criteria** — Conditions that must be met
- **Testable behaviors** — Specific actions and expected outcomes
- **User roles** — Who uses this feature and their permissions
- **Data requirements** — What data is needed
- **Integration points** — APIs, services, or systems involved

### 2. Test Types Needed

- **Unit tests** — Individual functions and utilities
- **Integration tests** — API endpoints and service interactions
- **E2E tests** — User-facing UI flows
- **API tests** — Endpoint contracts and error handling

### 3. Edge Cases & Error Scenarios

- Invalid inputs (empty, too long, special characters)
- Unauthorized access
- Network failures or timeouts
- Concurrent users or race conditions
- Boundary conditions
- Missing or null data
- State transitions (back navigation, refresh, etc.)

### 4. Structured Analysis Output

```text
Ticket: PROJ-1234
Summary: [ticket title]
Status: [current status]
Priority: [High/Medium/Low]
Test Types: Unit, Integration, E2E

Requirements:
1. [requirement 1]
2. [requirement 2]

Acceptance Criteria:
- [ ] [criterion 1]
- [ ] [criterion 2]

Test Scenarios:
- Happy Path: [description]
- Error Case: [description]
- Edge Case: [description]

Test Data Needed:
- [data item 1]
- [data item 2]

Dependencies:
- [dependency 1]
- [dependency 2]
```

## Updating Tickets

### When to Update

| Workflow Step | Jira Update |
| --- | --- |
| Start work | Transition to "In Progress" |
| Tests written | Comment with test coverage summary |
| Branch created | Comment with branch name |
| PR/MR created | Comment with link, link issue |
| Tests passing | Comment with results summary |
| PR/MR merged | Transition to "Done" or "In Review" |

### Comment Templates

**Starting Work:**

```text
Starting implementation for this ticket.
Branch: feat/PROJ-1234-feature-name
```

**Tests Implemented:**

```text
Automated tests implemented:

Unit Tests:
- [test file 1] — [what it covers]
- [test file 2] — [what it covers]

Integration Tests:
- [test file] — [endpoints/flows covered]

All tests passing locally. Coverage: XX%
```

**PR Created:**

```text
Pull request created:
[PR Title](https://github.com/org/repo/pull/XXX)

Ready for review.
```

**Work Complete:**

```text
Implementation complete.

PR merged: [link]
Test results: All passing (X/Y)
Coverage: XX%
```

## Best Practices

- Update Jira as you go, not all at once at the end
- Keep comments concise but informative
- Link rather than copy — point to PRs, test reports, and dashboards
- Use @mentions if you need input from others
- Check linked issues to understand full feature scope before starting
- If acceptance criteria are vague, ask for clarification before writing code
