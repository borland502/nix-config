# Vendor-specific schemas share commands while retaining their own field names.
{xdgBinHome}: let
  definitions = {
    bash = [
      {
        script = "log-bash.sh";
        timeout = 10;
      }
      {
        script = "log-thinking.sh";
        timeout = 30;
      }
    ];
    skill = [
      {
        script = "log-skill.sh";
        timeout = 10;
      }
    ];
  };
  cli = entry: {
    type = "command";
    command =
      "AGENT_NAME=copilot "
      + (
        if entry.script == "log-thinking.sh"
        then ""
        else "exec "
      )
      + ''bash "$HOME/.local/bin/ai-tools/${entry.script}"'';
    timeoutSec = entry.timeout;
  };
  editor = entry: {
    type = "command";
    command = ''bash "${xdgBinHome}/ai-tools/${entry.script}"'';
    env.AGENT_NAME = "copilot";
    inherit (entry) timeout;
  };
in {
  copilot = kind:
    builtins.toJSON {
      version = 1;
      hooks.postToolUse = map cli definitions.${kind};
    };
  vscode = kind: builtins.toJSON {hooks.PostToolUse = map editor definitions.${kind};};
}
