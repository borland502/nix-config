# gopwgen — Go CLI packaged for Nix.
#
# Reference pattern for Go tools in this repo (see ../README.md). buildGoModule
# needs no hand-rolled dependency derivation: `vendorHash` covers the whole
# module graph. Imported from github.com/borland502/gopwgen, which was retired once
# this became the source of truth.
{
  lib,
  buildGoModule,
}: let
  pname = "gopwgen";
  version = "0.1.0";
  modulePath = "github.com/borland502/gopwgen";
in
  buildGoModule {
    inherit pname version;

    # taskfile_integration_test.go exercises `task deploy/undeploy`, which is
    # not part of the Nix build and needs a Taskfile + task binary the sandbox
    # does not have. It stays in the tree for local `task test`, out of src here.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./go.mod
        ./go.sum
        ./main.go
        ./cmd
        ./internal
        ./pkg
        ./configs
      ];
    };

    vendorHash = "sha256-OQbAhMtHkNYb0uWLMaTYide5im3tKIH6DnxqDvvH7+A=";

    ldflags = [
      "-s"
      "-w"
      "-X ${modulePath}/internal/version.Version=${version}"
      "-X ${modulePath}/internal/version.Commit=nix"
      "-X ${modulePath}/internal/version.Date=1970-01-01T00:00:00Z"
    ];

    meta = {
      description = "Password and passphrase generator";
      mainProgram = pname;
      platforms = lib.platforms.linux ++ lib.platforms.darwin;
    };
  }
