# Skill validation checklist

Complete the relevant evidence gates for each changed skill before deployment.
Keep check records in a cache report; skill edits do not authorize publishing.

## Evidence and authoring

- [ ] Record realistic scenarios before the change and a no-guidance control
      for behavior claims. Document choices and rationalizations actually seen.
- [ ] State whether this is a behavior correction or reference/disclosure work.
      Do not fabricate a failed control or guaranteed cost improvement.
- [ ] Use a lowercase hyphenated name matching the folder, valid frontmatter,
      and a discriminating third-person trigger description.
- [ ] Retain essential gates and route conditional detail to focused references.
- [ ] Use a strong relevant example and only supporting resources needed by the
      workflow. Avoid narratives, duplicated manuals and unused scaffolding.
- [ ] Match guidance form to the demonstrated failure. For behavior-shaping
      wording, include a no-guidance control and at least five fresh samples per
      variant, manually reviewing flagged matches.
- [ ] Run realistic forward scenarios, including variations and missing-input
      cases; independently evaluate complex/risky skills when authorized.

## Mechanical validation

- [ ] Run the skill-creator bundled `scripts/quick_validate.py SKILL_DIRECTORY`.
- [ ] Verify every relative resource link, including moved reference links.
- [ ] Run Markdown lint and inspect renderer-sensitive examples/fences.
- [ ] Run model-agnostic and context-budget checks; record entry/body bytes.
- [ ] Execute changed scripts in isolated fixtures with meaningful assertions.
- [ ] Confirm user intent, persistent authorization and project/global scope.

## Refine and deliver

- [ ] Correct observed gaps and re-test affected scenarios before moving on.
- [ ] Record observed outcomes, artifact paths and material test limitations.
- [ ] Review the final diff for unrelated edits or private details.
- [ ] Finish the user's authorized deliverable. Commit, push, activate or
      contribute upstream only when that action is actually requested/authorized.
