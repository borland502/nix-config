{lib}: {
  python = builtins.path {
    path = ../../chezmoi/dot_local/lib;
    name = "agent-tools-lib";
    filter = source: type:
      (type == "directory" && builtins.baseNameOf source != "__pycache__")
      || (type == "regular" && lib.hasSuffix ".py" source);
  };
  shell = builtins.path {
    path = ../../chezmoi/dot_local/lib/shell;
    name = "agent-tools-shell-lib";
  };
}
