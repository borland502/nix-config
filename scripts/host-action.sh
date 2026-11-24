#!/usr/bin/env zsh
emulate -L zsh
setopt errexit no_unset pipe_fail
action=$1 platform=$2 host=$3 system_flake=$4 home_flake=$5 home_app=$6 dev_attr=$7
case $platform in
darwin | nixos | standalone | devcontainer) ;;
*)
	printf 'Unknown platform: %s\n' "$platform" >&2
	exit 2
	;;
esac
if [ "$action" = upgrade ]; then
	nix flake update
fi
run_wsl() {
	if [ "$host" = wsl ]; then
		NIX_CONFIG='experimental-features = nix-command flakes' "$@"
	else
		"$@"
	fi
}
case $action in
build | dry-build)
	case $platform in
	devcontainer)
		if [ "$action" = dry-build ]; then
			nix build ".#homeConfigurations.${dev_attr}.activationPackage" --dry-run
		else
			nix build ".#homeConfigurations.${dev_attr}.activationPackage"
		fi
		;;
	darwin)
		if [ "$action" = dry-build ]; then
			darwin-rebuild build --dry-run --flake ".#$host"
		else
			darwin-rebuild build --flake ".#$host"
		fi
		;;
	nixos)
		if [ "$action" = dry-build ]; then
			run_wsl nixos-rebuild dry-build --flake "$system_flake"
		else
			run_wsl nixos-rebuild build --flake "$system_flake"
		fi
		;;
	standalone) run_wsl nix run "$home_app" -- build --flake "$home_flake" ;;
	esac
	;;
switch | switch-update-brew | home-switch | upgrade)
	case $platform in
	devcontainer) nix run .#home-manager -- switch --flake ".#$dev_attr" -b bak-devcontainer ;;
	darwin)
		if [ "$action" = switch-update-brew ]; then brew update --quiet; fi
		zsh -f scripts/darwin-switch-tolerant.sh ".#$host"
		;;
	nixos) zsh -f scripts/nixos-switch-tolerant.sh "$system_flake" ;;
	standalone)
		run_wsl nix run "$home_app" -- switch --flake "$home_flake" -b backup
		if [ "$action" = home-switch ] || [ "$action" = upgrade ]; then
			helper="$HOME/.local/bin/ensure-nix-zsh-shell"
			if [ -x "$helper" ]; then "$helper"; else printf 'Note: ensure-nix-zsh-shell not deployed yet; login shell left unchanged.\n'; fi
		fi
		;;
	esac
	;;
*)
	printf 'Unknown host action: %s\n' "$action" >&2
	exit 2
	;;
esac
if [ "$action" = upgrade ]; then
	agents="$HOME/.local/bin/update-agent-clis"
	if [ -x "$agents" ]; then "$agents"; else printf 'note: update-agent-clis not deployed; skipping agent CLI update\n'; fi
fi
