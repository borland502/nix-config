---
description: Weekly nix flake input update + build smoke-check for the nix-config repo. Reports input bumps and failures; never commits or switches.
argument-hint: "[input-name]   # optional: update only this flake input"
---

Refresh and smoke-test this repo's flake inputs. **Do not commit, push, or
switch** — report only; the user decides whether to keep the lock change.

Working dir: `/Users/42245/.config/nix`.

1. Pre-check: `git -C /Users/42245/.config/nix --no-pager diff --stat`. If
   `flake.lock` is already modified, report that and stop (don't clobber an
   in-progress change).
2. Update inputs: `nix flake update` for all, or `nix flake update $ARGUMENTS`
   when an input name was passed.
3. Show what moved: `git -C /Users/42245/.config/nix --no-pager diff flake.lock`
   — summarize the input bumps (old→new short rev); don't dump the whole file.
4. Smoke-test **without switching**: a dry/eval build of the darwin config, e.g.
   `nix build .#darwinConfigurations.$(scutil --get LocalHostName).system --dry-run`
   (or the repo's check task). Never run `task switch` / `darwin-rebuild switch`.
5. If quick, run `task lint:nix`.

Output:

- **Inputs bumped:** input — old→new (short rev)
- **Build smoke:** pass / fail (+ first error line if fail)
- **Recommendation:** keep & switch, or revert (`git checkout flake.lock`)

If the build fails, leave `flake.lock` as-is and clearly flag it so the user can
revert. Do not attempt to fix build errors autonomously.
