---
name: flow-writing-skills
description: Use when creating new skills, editing existing skills, or verifying skills work before deployment
---

# Writing skills

Create reusable guidance that changes decisions or supplies needed reference
material. Keep discovery cheap: a discriminating description, a compact entry
with essential gates, and topic-specific references loaded only when needed.
Understand [flow-test-driven-development](../flow-test-driven-development/SKILL.md)
before authoring behavior guidance. Use the available skill-creator workflow for
frontmatter, packaging and its bundled validator.

## Establish evidence before editing

Write realistic scenarios before changing instructions. For behavior changes,
run a no-guidance control and capture actual choices and rationalizations before
writing the correction. For complex or risky guidance, use independent scoped
evaluators when delegation is available and authorized. Give them the request,
skill and minimum raw artifacts, without the intended answer or suspected fix.
Use isolated fixtures and no live external side effects by default.

If the control already succeeds, do not claim a reasoning defect or invent a
failure. Reference/disclosure refactoring can proceed against retrieval,
constraint preservation and application scenarios; describe that narrower goal
and verify it. A size reduction alone does not prove lower bills or better
reasoning. Do not add universal rules for hypothetical errors.

For discipline guidance, combine realistic pressures and inspect compliance.
For techniques, test application and missing information. For patterns, include
counterexamples. For references, verify retrieval and a concrete use. Read
[behavioral testing](references/behavioral-testing.md) for these methods and
wording micro-tests; micro-tests require a no-guidance control and at least five
fresh samples per variant, with every flagged match read manually. They do not
replace realistic pressure scenarios.

## Write and disclose progressively

- Name the folder and frontmatter consistently with lowercase letters, digits
  and hyphens. Require `name` and `description`; describe when the skill applies
  in third person, preferably starting “Use when”. Keep the description focused
  on triggers, without replacing the actual workflow.
- Keep purpose, essential constraints and reference routing in `SKILL.md`.
  Target roughly 4 KB here; the repository's entry limit is 5,000 bytes.
  Split substantial recipes by topic rather than moving one giant manual that
  must be read for every case. Link resources relative to the entry.
- Use one strong, relevant example; deterministic repeated mechanics belong in
  scripts. Avoid session stories, duplicated tutorials, multi-language versions
  and force-loading supporting resources with `@` references.
- Apply guidance to the authorized task. Existing authorization persists; do
  not require a new design approval, commit, push, deployment or live service
  action merely because a skill is being edited.
- Keep project-only guidance in explicitly opted-in project skill directories.
  Generic templates are distributed separately from globally discovered skills.

Read [discovery and examples](references/discovery-and-examples.md) when tuning
descriptions, examples, diagrams or file organization. For persuasion or
discipline failures, consult [persuasion principles](persuasion-principles.md)
only when relevant; use a narrow correction supported by the observed behavior.

## Validate each skill before delivery

Run the skill-creator bundled `scripts/quick_validate.py SKILL_DIRECTORY` and
the repository's reference, Markdown, model-agnostic and context-budget checks.
Execute new scripts in isolated fixtures. Test realistic forward scenarios with
the revised skill and record limits alongside observed outcomes. Re-test any
supported correction; retain no untested instruction change.

Use [validation checklist](references/validation-checklist.md) for the detailed
authoring checklist and [subagent testing](testing-skills-with-subagents.md)
for evaluator setup. Finish validation for each edited skill before deployment;
this does not authorize activation or publishing. Record scenarios, byte counts
and reports in `~/.cache/codex` or an existing ignored operational directory.
