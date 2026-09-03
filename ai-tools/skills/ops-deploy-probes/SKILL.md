---
name: ops-deploy-probes
description: Use BEFORE writing or executing a deployment, migration, or infrastructure-change plan, and whenever you are about to add another dry run instead of measuring. Sets the verification budget from the target's environment: dev servers, cloud dev instances, sandboxes and lab hosts get an active-probe budget — read live state, create a throwaway resource, run the real call against a scratch name — instead of stacked dry runs, which prove syntax only. Production keeps the conservative path. Also use when a plan has failed twice for a reason nobody predicted.
---

# Probe-First Deployment Plans

## Overview

A deployment plan is a set of claims about a live system. `--dry-run`, `diff`,
`--validate`, and `plan` subcommands check that your *template* is well-formed.
They do not check that your *model of the platform* is right — and that is where
these plans actually fail.

The correction this skill encodes: **on a development or non-production target,
buy the answer with a probe instead of inferring it from a dry run.** The
conservative default — never touch anything, verify only on paper — is correct
for production and expensive everywhere else. A throwaway resource that settles
a question in ninety seconds is cheaper than a plan that fails three times.

**Announce at start:** "I'm using the ops-deploy-probes skill to set the
verification budget for this plan."

## Step 1 — Classify the target, and say so out loud

Write the classification into the plan before the first task. Signals:

**Development / non-production** — probe budget applies:

- The environment name or resource tag carries `dev`, `test`, `qa`, `sandbox`,
  `staging`, `scratch`, `tmp`, `demo`, `lab`, `preview`, `ephemeral`, or a
  ticket/branch identifier.
- A hostname from the personal/lab inventory, or any host reachable only from
  the local network.
- A cloud account, project, or subscription designated non-production, or a
  stack whose only consumers are engineers.
- A resource you or your team created for this piece of work and can recreate
  from source.

**Production — or unclassified** — conservative path, no probes without
explicit approval:

- `prod`, `production`, `live`, `main`, a customer-facing domain, or no
  environment marker at all.
- Anything holding data you cannot regenerate, or that other teams consume.
- Shared infrastructure that merely *lives* in a dev account: shared DNS zones,
  shared container registries, shared parameter stores, org-level IAM.

**If you cannot classify it, it is production.** Ask; do not guess. State the
classification and the evidence for it (`the stack name is <name>-dev6`, `the
tag Environment=sandbox`), not just the verdict.

## Step 2 — On a non-production target, the default flips

Replace "assume, then dry-run" with "measure, then plan". A probe is legitimate
when it is **reversible, scoped to the environment, and cheap**. Prefer, in
order:

1. **Read live state** rather than the repository, the template, or an artifact
   you found lying around. The deployed thing is the source of truth.
2. **Run the real read-side call** — `describe`, `list`, `get`, `status`,
   `--version`, an actual HTTP request to the actual endpoint.
3. **Create a throwaway resource** with a unique scratch name, ask it the
   question, then delete it. This is the highest-value probe and the most
   under-used: it converts a platform-behavior debate into a measurement.
4. **Execute one real step against a scratch name** and inspect the result,
   instead of simulating the whole sequence.

Only after those fail to answer the question does a dry run earn its place.

## Step 3 — The dry-run failure modes to plan around

These are the ones that have actually cost time. Each has a probe that settles
it directly:

- **The platform enforces its own bookkeeping, not physical reality.** A
  uniqueness or ownership guard can be enforced against a control-plane record
  that outlives the object. Deleting the object out of band does not free the
  name. *Probe: create a throwaway stack/resource that reproduces the conflict
  and read the exact error.*
- **Paginated reads truncate silently.** A `describe-*` call returned 100 of 128
  resources; the missing 28 were the ones that mattered, and nothing in the
  output said it was partial. *Probe: use the paginating `list-*` call, then
  assert the count against an independently-known total before planning on it.*
- **A found artifact is not necessarily the current artifact.** A template,
  manifest, or asset bundle recovered from a bucket or cache can be semantically
  stale while looking authoritative. *Probe: re-synthesize or re-render it now
  and diff against what you found.*
- **Request/size/shape limits bite at execution, not at validation.** Body-size
  ceilings, resource-count ceilings, and unsupported-resource-type lists are
  enforced by the service, not by your local validator. *Probe: submit the real
  request in a non-executing mode the service itself provides, or against a
  scratch target, and read its rejection.*
- **Repeated failure means the model is wrong, not the luck.** After two
  attempts that failed for reasons you did not predict, stop retrying variants.
  The next action is a probe aimed at the assumption all the attempts shared.

## Step 4 — Guardrails that hold even in dev

The probe budget widens what you may *try*. It does not remove the confirmation
gate on:

- Deleting or overwriting anything holding data you cannot regenerate — a
  database, a bucket with uploads, a volume — even in a dev account.
- Anything other engineers are actively using: a shared dev environment mid-demo,
  a branch deployment someone is testing against.
- Changes whose blast radius leaves the environment: IAM, org policy, DNS at a
  shared zone, network peering, a shared registry tag, a package published to an
  internal or public index.
- Anything that costs materially to create, or that you cannot delete afterward.
- Credentials: probe with the environment's own scoped credentials, never by
  widening a role to make a probe work.

Before any probe that creates or mutates, state in one line: what it creates,
how it is named, how it is deleted, and what happens if the delete fails. If you
cannot write the cleanup step, the probe is not reversible — treat it as a
production action.

## Step 5 — Record measurements as evidence, not prose

Every load-bearing claim in the plan carries its provenance. Two tags, and only
two:

```markdown
- **Measured** (2026-09-03): `aws cloudformation list-stack-resources --stack-name <s>`
  → 128 resources; the earlier `describe-stack-resources` capture had 100.
  Mapping must use the 128.
- **Assumed**: the nested stack's outputs are stable across the deploy.
  Not verified — a probe would require the deploy itself.
```

An `Assumed` tag is allowed; an unlabeled claim is not. When the plan is
reviewed, `Assumed` items are the review surface — that is the whole point of
distinguishing them. Carry the measurements into the handoff or the plan file in
`~/.cache/<agent>/` so the next session inherits the evidence instead of
re-deriving it.

## Step 6 — What still goes in the plan

Probing does not replace planning. It changes what the plan is allowed to assert.
Keep the ordinary structure from
[flow-writing-plans](../flow-writing-plans/SKILL.md), and add:

- The environment classification and its evidence (Step 1).
- A **Preflight** task, before the first mutating task, listing each probe as a
  runnable command with its expected output — the same rigor a test step gets.
- A rollback or recovery note per mutating task: what state it leaves behind if
  it fails halfway, and the command that undoes it.
- The `Measured` / `Assumed` ledger (Step 5).

## Anti-patterns

- Stacking a third dry run to answer a question a `list` call would answer.
- Treating "the diff looks right" as verification of anything but the diff.
- Planning against the repository's template when the deployed template is
  reachable and may differ.
- Reporting a probe you did not run, or a count you did not read, as measured.
- Widening the classification to justify a probe: a shared dev environment that
  other people are using is not yours to experiment on.
- Running a probe in production because the dev environment was inconvenient.

## References

- [flow-writing-plans](../flow-writing-plans/SKILL.md) — plan structure and task
  right-sizing; this skill sets the verification budget those tasks inherit.
- [flow-verification-before-completion](../flow-verification-before-completion/SKILL.md)
  — evidence before assertions, at completion time.
- [flow-systematic-debugging](../flow-systematic-debugging/SKILL.md) — when the
  deployment has already failed and you are diagnosing rather than planning.
- [sec-credentials](../sec-credentials/SKILL.md) — obtain the environment's
  credentials from disk instead of asking or widening a role.
- [shell-pitfalls](../shell-pitfalls/SKILL.md) — quoting and dialect traps that
  make a probe report the wrong answer.
