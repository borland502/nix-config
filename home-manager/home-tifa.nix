{pkgs, ...}: {
  # Standalone Home Manager entry point for "tifa", the CachyOS box that has no
  # nixosConfigurations entry (see README "Available hosts"). Everything shared
  # with the other generic-Linux hosts stays in home.nix; this file carries only
  # what is scoped to tifa alone, so the `jhettenh@linux` attr the other
  # non-NixOS hosts activate through is unaffected.
  imports = [./home.nix];

  home.packages = [
    # Google Cloud CLI: gcloud, gsutil, bq, plus the docker/git credential
    # helpers. Only tifa talks to GCP, which is why this is not in common.nix
    # beside awscli2.
    #
    # Installing it into the profile is the whole wiring. The binaries land in
    # ~/.nix-profile/bin, already on PATH; the package ships
    # share/zsh/site-functions/{_gcloud,_gsutil}, and
    # ~/.nix-profile/share/zsh/site-functions is on $fpath ahead of the
    # compinit in ~/.zshrc, so completion loads with no init snippet — the same
    # path awscli2's _aws takes. Bash and fish completions ship in the same
    # layout for anything that reads the profile's share dirs.
    pkgs.google-cloud-sdk

    # Element, the Matrix client. Desktop GUI, so it is scoped here rather than
    # to common.nix, which also feeds WSL and the headless hosts.
    #
    # Note the name: the ATTRIBUTE is element-desktop. On Arch/CachyOS the bare
    # name `element` is a DIFFERENT program entirely -- Kushview Element, a
    # modular audio plugin host from the pro-audio repo -- so `pacman -S
    # element` installs the wrong thing (done accidentally on 2026-09-05). The
    # distro package for this one is also called element-desktop. Keeping it in
    # the flake rather than pacman avoids the collision for good.
    pkgs.element-desktop
  ];
}
