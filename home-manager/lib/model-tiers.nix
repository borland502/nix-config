# Capability tiers (high/mid/low) resolved to OpenAI model slugs, shared by
# the Copilot CLI and the Codex CLI: both serve the same GitHub/OpenAI
# sol/terra/luna family under identical slugs (Codex's catalog, per
# `codex debug models`, lists gpt-5.6-{sol,terra,luna} 2026-09-25). This is the
# one place to bump them when a new generation ships — together with
# ANTHROPIC_DEFAULT_*_MODEL in chezmoi/dot_claude/settings.json and the table
# in agent-reference.md § Model Tiers (see AGENTS.md).
{
  openai = {
    high = "gpt-5.6-sol";
    mid = "gpt-5.6-terra";
    low = "gpt-5.6-luna";
  };

  # Claude tier aliases as used in ai-tools/agents `model:` frontmatter.
  claudeAliasTier = {
    opus = "high";
    sonnet = "mid";
    haiku = "low";
  };
}
