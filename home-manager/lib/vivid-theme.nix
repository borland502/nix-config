# Vivid theme generated from chezmoi/dot_config/colors/monokai.toml.
# common.nix runs `vivid generate` against this and bakes the result into
# LS_COLORS, which `ls`, `eza`, `tree`, and friends pick up.
{
  lib,
  pkgs,
}: let
  c = import ./colors.nix;
  hex = s: lib.removePrefix "#" s;
in
  pkgs.writeText "monokai-spectrumish-vivid.yml" ''
    colors:
      base00: '${hex c.base00}'
      base01: '${hex c.base01}'
      base02: '${hex c.base02}'
      base03: '${hex c.base03}'
      base04: '${hex c.base04}'
      base05: '${hex c.base05}'
      base06: '${hex c.base06}'
      base07: '${hex c.base07}'
      base08: '${hex c.base08}'
      base09: '${hex c.base09}'
      base0A: '${hex c.base0A}'
      base0B: '${hex c.base0B}'
      base0C: '${hex c.base0C}'
      base0D: '${hex c.base0D}'
      base0E: '${hex c.base0E}'
      base0F: '${hex c.base0F}'

    core:
      normal_text: {}
      regular_file: {}
      reset_to_normal: {}

      directory:
        foreground: base0D
        font-style: bold

      symlink:
        foreground: base0C

      multi_hard_link: {}

      fifo:
        foreground: base00
        background: base0C

      socket:
        foreground: base00
        background: base08

      door:
        foreground: base00
        background: base08

      block_device:
        foreground: base0C
        background: base01

      character_device:
        foreground: base08
        background: base01

      broken_symlink:
        foreground: base00
        background: base08

      missing_symlink_target:
        foreground: base00
        background: base08

      setuid: {}
      setgid: {}
      file_with_capability: {}
      sticky_other_writable: {}
      other_writable: {}
      sticky: {}

      executable_file:
        foreground: base08
        font-style: bold

    text:
      special:
        foreground: base00
        background: base0A

      todo:
        font-style: bold

      licenses:
        foreground: base04

      configuration:
        foreground: base0B

      other:
        foreground: base0A

    markup:
      foreground: base0A

    programming:
      source:
        foreground: base0B

      tooling:
        foreground: base0B

        continuous-integration:
          foreground: base0A

    media:
      foreground: base09

    office:
      foreground: base0A

    archives:
      foreground: base08
      font-style: underline

    executable:
      foreground: base08
      font-style: bold

    unimportant:
      foreground: base04
  ''
