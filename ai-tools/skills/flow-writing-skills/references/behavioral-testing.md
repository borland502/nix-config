# Behavioral testing

Use this reference before changing behavior guidance, or when a complex skill
needs realistic independent validation. Keep raw requests, observed decisions,
scoring notes and substantial output in named cache files. Do not copy private
session transcripts into this public repository.

## Choose the test for the skill

| Skill type | Evidence to collect |
| --- | --- |
| Discipline | Understanding plus compliance under combined realistic pressures |
| Technique | Application, variations and missing-information cases |
| Pattern | Recognition, application and counterexamples |
| Reference | Retrieval, correct application and gaps in common use cases |

For discipline skills, combine pressures such as time, sunk cost and exhaustion
without authorizing unsafe live actions. Record actual choices and verbatim
rationalizations. “It reads clearly” and academic recall alone do not establish
that an agent can use the guidance.

## Baseline, correction and forward test

1. Write realistic scenarios before authoring the correction. Run a control
   without the guidance and observe what happens. Do not supply the expected
   answer, suspected bug or proposed fix to an independent evaluator.
2. For an observed behavior failure, write the smallest instruction that
   addresses its demonstrated cause. For reference/disclosure refactors whose
   controls succeed, preserve constraints and test retrieval/application; do not
   invent a failed baseline or claim a reasoning improvement.
3. Run the revised skill against the same task class and new variations. Inspect
   actual outcomes, artifacts and omissions. A model repeating a rule is not
   proof that its actions followed it.
4. Correct only supported gaps and repeat the affected scenarios. Validate each
   changed skill before deploying it. User authorization governs any activation,
   commit, push or live service operation.

For complex or risky skills, use independent scoped agents when delegation is
authorized and available. Give each the realistic request, the candidate skill
and minimum raw artifacts. Use a disposable workspace for generated output.
The detailed scenario method lives in
[testing skills with subagents](../testing-skills-with-subagents.md).

## Match wording to an observed failure

| Failure | Instruction shape |
| --- | --- |
| Knows a discipline rule but skips it under pressure | Explicit prohibition with observed rationalizations and red flags |
| Produces the wrong output shape | Positive recipe stating required parts and order |
| Omits a required element | Required slot in the actual output template |
| Needs conditional behavior | Condition keyed to an observable predicate |

Do not prescribe discipline-style prohibitions for every formatting problem.
Express real conditions directly rather than appending vague “unless it matters”
clauses. If a bound applies to one output part, structurally scope it to that
part; an exemption sentence can still prime the wrong behavior.

For a demonstrated discipline violation, capture rationalizations in a table
and address the actual workarounds explicitly. For example, retaining an
untested instruction as “reference” does not satisfy validation. Close observed
loopholes without accumulating hypothetical prohibitions. Consult
[persuasion principles](../persuasion-principles.md) only for that specific need.

## Wording micro-tests

For behavior-shaping wording, run fresh-context samples before full scenarios:

1. Use the realistic containing system context and a request that tempts the
   observed failure, one independent sample per call.
2. Include a no-guidance control. If it does not fail, stop claiming the guidance
   corrects a defect; reference/disclosure work has a different evidence claim.
3. Run at least five repetitions per variant. A single favorable sample is weak
   evidence; note variance across interpretations.
4. Read every flagged match manually. Quoted examples and template echoes can
   produce false positives in automated scores.
5. Use full realistic forward scenarios for the final gate. Micro-tests do not
   replace pressure testing for discipline changes.

Report what was measured and what remains unverified. Controls that already
succeed, small samples, paper exercises and unavailable tools all limit causal
claims. Reduced entry bytes do not by themselves establish quality or savings.
