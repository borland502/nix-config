#!/usr/bin/env bash
# Keep private detail out of this public repo. Two rules:
#
#   A. Every chezmoi source under chezmoi/Development/ must be an encrypted_*
#      file. That tree mirrors a private work checkout, so its contents — repo
#      layout, internal hosts, ticket conventions — must never land here in the
#      clear.
#
#   B. No value stored in a SOPS secret may appear verbatim anywhere else in
#      the repo. This covers internal URLs and hostnames as well as tokens: if
#      a value was worth encrypting once, restating it in a doc undoes that.
#      Rule B is what would have caught the CMS Jira and Confluence hosts
#      sitting in the clear in three ai-tools/skills files while the same
#      values were already encrypted in secrets/ops-agent.yaml.
#
# Rule B needs the age key. Without it the rule is skipped loudly rather than
# passing silently — pre-commit runs locally, where the key exists, and that is
# the gate that matters.
set -euo pipefail

fail=0

# --- Rule A: the private work tree stays encrypted ---------------------------
if [ -d chezmoi/Development ]; then
	while IFS= read -r f; do
		case "${f##*/}" in
		encrypted_*) ;;
		*)
			printf 'secret-hygiene: unencrypted file in the private work tree: %s\n' "$f" >&2
			fail=1
			;;
		esac
	done < <(find chezmoi/Development -type f)
fi

# --- Rule B: no encrypted value restated in the clear ------------------------
key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [ ! -f "$key_file" ]; then
	printf 'secret-hygiene: no age key at %s — skipping the SOPS value scan.\n' "$key_file" >&2
else
	export SOPS_AGE_KEY_FILE="$key_file"
	while IFS= read -r sf; do
		case "$sf" in
		*.yaml | *.yml) plain=$(sops -d "$sf" 2>/dev/null | yq -r '.. | select(tag == "!!str") | (path | join(".")) + "\t" + .' 2>/dev/null || true) ;;
		*.json) plain=$(sops -d "$sf" 2>/dev/null | yq -p json -r '.. | select(tag == "!!str") | (path | join(".")) + "\t" + .' 2>/dev/null || true) ;;
		*.toml) plain=$(sops -d "$sf" 2>/dev/null | yq -p toml -r '.. | select(tag == "!!str") | (path | join(".")) + "\t" + .' 2>/dev/null || true) ;;
		*) continue ;;
		esac
		[ -n "$plain" ] || continue

		while IFS=$'\t' read -r keypath value; do
			# SOPS files mix credentials with ordinary config — cache dirs,
			# regions, shell names — and those legitimately recur all over the
			# repo. Only key names that denote a credential or an endpoint are
			# in scope; everything else would be noise, and noise gets ignored.
			#
			# Matched on the LEAF key, not the whole path. Matching the path made
			# the table name leak into the decision: every key under
			# secrets/hosts.toml's [hosts.*] tables matched *host*, so ordinary
			# fields like identityfile were scanned and flagged for holding
			# ~/.ssh/id_remoting — a path that is *supposed* to appear in
			# sshd.nix and the provisioning script. The leaf keeps the intent
			# (hostname, api_url, admin_password) without inheriting it from a
			# parent that merely happens to be called "hosts".
			leafkey=${keypath##*.}
			case "${leafkey,,}" in
			*url* | *host* | *endpoint* | *token* | *secret* | *password* | *passwd* | *api_key* | *apikey* | *_pat) ;;
			*) continue ;;
			esac

			# Short or whitespace-bearing values produce noise, not signal.
			[ ${#value} -ge 8 ] || continue
			case "$value" in *[[:space:]]*) continue ;; esac

			# A stored URL leaks just as badly as its bare hostname — and the
			# bare host is the form that actually shows up in prose. Scan the
			# full value AND, for a URL, the host on its own. Without this the
			# check misses exactly what it was written to catch.
			needles=("$value")
			case "$value" in
			*://*)
				host=${value#*://} # strip scheme
				host=${host%%/*}   # strip path
				host=${host##*@}   # strip userinfo
				host=${host%%:*}   # strip port
				[ ${#host} -ge 8 ] && needles+=("$host")
				;;
			esac

			for needle in "${needles[@]}"; do
				hits=$(rg --fixed-strings --line-number --no-messages \
					--glob '!.git' \
					--glob '!secrets/**' \
					--glob '!hosts/*/secrets/**' \
					--glob '!**/*.age' \
					--glob '!result' \
					--glob '!result-*' \
					--glob '!scripts/check-secret-hygiene.sh' \
					-- "$needle" . | cut -d: -f1,2 || true)

				if [ -n "$hits" ]; then
					# Report the location and which secret leaked — never the value.
					printf 'secret-hygiene: %s (%s) appears in the clear:\n' "$sf" "$keypath" >&2
					printf '%s\n' "$hits" | sed 's/^/  /' >&2
					fail=1
				fi
			done
		done <<<"$plain"
	done < <(find secrets hosts -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.toml' \) -path '*secrets*' 2>/dev/null)
fi

if [ "$fail" -ne 0 ]; then
	cat >&2 <<'MSG'

This repo is public. Encrypt the value instead of inlining it:
  - work-repo files  -> chezmoi/Development/**, named encrypted_<name>
                        (age; see the existing encrypted_CLAUDE.md.age)
  - URLs, hosts, tokens -> secrets/*.yaml via `sops`, declared in
                        home-manager/modules/sops.nix, then read at runtime
                        from the materialized path
Docs should point at the materialized path, never restate the value.
MSG
	exit 1
fi

echo 'secret-hygiene OK: work tree encrypted, no SOPS value restated in the clear'
