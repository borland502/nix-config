---
name: cli-xh
description: Use when constructing or inspecting HTTP/JSON requests with xh, testing an endpoint, or choosing between xh, curl, and existing authenticated service helpers.
---

# Make explicit HTTP requests with xh

xh makes headers, query parameters, and JSON bodies readable at the command line.
Honor an explicitly requested tool.

## Choose a tool

```text
Need a network operation?
|-- Existing authenticated service workflow/helper -> use that helper
|-- Ad hoc HTTP request with readable JSON -> xh
|-- Established curl script or a curl-specific protocol/option -> curl
|-- DNS record lookup -> doggo
`-- Listening process or port reachability -> lsof or a scoped network probe
```

Use the existing credential workflow for protected endpoints. HTTP success and
DNS resolution are separate checks; see [doggo](../cli-doggo/SKILL.md).

## Use explicit methods and bounded waits

```sh
xh --ignore-stdin --check-status --timeout=10 --body --pretty=none GET http://127.0.0.1:8080/health 'detail==true'
xh --offline --ignore-stdin POST http://127.0.0.1:8080/items name=example 'enabled:=true'
```

The second command prints a request without sending it. Remove `--offline` only
when the task calls for the write. `key==value` is a query parameter;
`key=value` is a string body field; `key:=value` is typed JSON. Quote shell
metacharacters.

Always name the HTTP method: adding body fields can change the inferred method
to POST. Use `--ignore-stdin` in automation unless stdin is deliberately the body.
For a piped/file body, omit that flag and supply the intended input.

`--check-status` makes 4xx exit 4 and 5xx exit 5. Treat those as HTTP failures,
not empty successful results. Capture JSON with `--body --pretty=none` and parse
with jq; avoid including authentication headers in verbose output or transcripts.

[Upstream](https://github.com/ducaale/xh)
