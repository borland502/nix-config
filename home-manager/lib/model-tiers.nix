# Capability tiers (high/mid/low) for the OpenAI-family slugs shared by the
# Copilot CLI and the Codex CLI. A tier names a model *family*, not a version:
# at activation scripts/resolve-model-tiers.py picks the newest listed
# `gpt-<version>-<family>` from Codex's live catalog
# ($CODEX_HOME/models_cache.json), so tiers move to each new generation without
# a repo edit and never age into "Legacy" models.
#
# `floor` is the fallback when no catalog is readable (fresh host, Linux/WSL
# without Codex) and the minimum the resolver will ever pick. It is also the
# build-time slug baked into Codex custom agents before activation resolves
# them. Raise it when activation warns that a floor is behind the catalog.
# Claude needs no entry: its opus/sonnet/haiku aliases already float to the
# newest model of each tier (no ANTHROPIC_DEFAULT_*_MODEL pins; see AGENTS.md).
{
  openai = {
    family = {
      high = "sol";
      mid = "terra";
      low = "luna";
    };
    floor = {
      high = "gpt-6.1-sol";
      mid = "gpt-6.1-terra";
      low = "gpt-6-luna";
    };
  };

  # Claude tier aliases as used in ai-tools/agents `model:` frontmatter.
  claudeAliasTier = {
    opus = "high";
    sonnet = "mid";
    haiku = "low";
  };
}
