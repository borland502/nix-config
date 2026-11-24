---
name: flow-brainstorming
description: "You MUST use this before any creative work - creating features, building components, adding functionality, modifying behavior, or planning anything new, in software or out of it (a talk, a business, a renovation)."
---

# Brainstorming

You are very good at building. You build what you believe your human
partner wants, and that belief is usually thinner than it feels. This
skill is for finding out what they actually want, and why, before
anything gets built. When you understand the why, you make the hundred
decisions they never mention the way they would have made them.

Brainstorming is a **high**-tier role, which is the session default. If
this session runs on a lower tier, switch up with `/model` first.

## First: What Do You Actually Know?

- **Everything that matters is in the request** ("make the icon
  cornflower blue"): a quick, clear task. Do it, and say what you did.
- **Something non-trivial is missing:** start the conversation.

Before you start implementing, you must, in order:

1. Lay out the approaches in a message of their own, and have your
   human partner pick one.
2. Write the design doc, short or full.
3. Get their approval of that doc.
4. Prepare a plan for the approved work. For software, invoke the
   nix-config-tools:flow-writing-plans skill. For other domains, outline
   the steps, owners, resources, and checks for success.

If nothing is open when you write your first message and there's one
sensible way, steps 1 to 3 happen in that message. Two things aren't
implementing: a spike they said yes to, and doing what they asked once
they've opted out of the questions.

## Read As You Go

- [first-message.md](references/first-message.md): look before you ask,
  and how the first message is built and ends. Read before replying.
- [conversation.md](references/conversation.md): when to ask, laying out
  the approaches, show-don't-tell, spikes, playing it back, and when to
  offer the visual companion. Read before your second message.
- [design-doc.md](references/design-doc.md): sizing the work, the written
  design, where it goes, and the builder check. Read before writing up.
- [visual-companion.md](visual-companion.md): only after they accept the
  browser companion.

<HARD-GATE>
Nothing gets built until your human partner approves the design doc:
the short one for a small change, the full one for a project.
Building includes writing product code, scaffolding, installing
dependencies, creating projects, and invoking an implementation skill.
Reading and exploring are fine.

Two exceptions. If they opted out of the questions, the skill is done
and the gate goes with it. A spike they said yes to may be built; it
stays labeled throwaway, and keeping what it produced is a new request
that comes back through this gate.

After the design doc is approved, the next step is a plan for that
domain. For software work, invoke nix-config-tools:flow-writing-plans
before any implementation skill. For other work, plan the steps, owners,
resources, and checks for success without requiring a coding workflow.
</HARD-GATE>

## Red Flags

| Thought | Reality |
|---------|---------|
| "I'll offer a menu of what they might want" | Options steer. Ask them to describe it first. |
| "I'll fill in sensible defaults" | Good. Say them out loud. A default they never heard is one they couldn't reject. |
| "I've answered their questions, so I'll write the doc" | Lay out the approaches first, in a message of their own (or, when nothing was open from the start, in your first message's short design). |
| "I should explain the process first" | Ask your question. The process shows itself. |
| "They said 'sounds good' to the idea" | Approval covers what you showed them. A design doc you haven't written isn't approved. |
| "The spike works, I'll keep building on it" | Keeping it is a new request. Back through the gate. |
