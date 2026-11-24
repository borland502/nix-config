# Sizing and writing the design

## Size the Work

Once you understand what they want and they've picked an approach, say
how big the work is in plain words. They can override it.

| Size | The design doc |
|------|----------------|
| A small change | a short one: what you already covered together, written down |
| A project | the full written design (below) |

Short or full, the design doc has an **Approaches** part: the two or
three ways you considered building it, what each trades off, which one
they picked, and why. They pick in the conversation, before you write
the doc.

If it grows mid-task, stop, say so, and step up a size.

If this is really several independent projects, say so, agree on an
order, and brainstorm them one at a time.

## The Written Design

Write a plain document a talented builder in the domain could plan
from without going back to your human partner. Cover:

- intent and the why
- goals, non-goals, anti-goals
- constraints
- approaches (above)
- the parts of the how they decided, as they decided them
- what's left to the builder

For a small change, the short design covers the same points in a line
or two each and goes straight to your human partner, without the
builder check.

**Where it goes:**
`~/.cache/copilot/YYYY-MM-DD-<repository-or-ticket>-<topic>-design.md`.
Do not commit it unless your human partner explicitly asked for it as a
tracked repository deliverable. Their preferences for the location
override this default.

**Builder check** (for a project): dispatch a fresh subagent with
[builder-check-prompt.md](../builder-check-prompt.md). Dispatch it on the
**mid** tier: it is one read of a document, not a design decision, and an
omitted model inherits the session's high tier (resolve tiers via
`~/.config/instructions/agent-reference.md` § Model Tiers). When you tell
your human partner you're writing it up, say a reviewer will read it
first and you may come back once with a few questions. Don't hand over
the document until the check is back. Sort what the builder asks into
three piles:

- **Answered already** by the conversation or the project: put the answer
  in the document.
- **Minor:** a sensible builder could settle it without changing what gets
  built. Settle it yourself and mark it in the document as your call.
- **Theirs:** only your human partner can answer it, and the answer changes
  what gets built.

Bring the "theirs" pile in one message, most important first. Update the
document with their answers, then hand it over with a short list of the
calls you made so they can check those while reading. That's the only
round of questions the check produces. Without a subagent tool, read the
document as that builder yourself.
