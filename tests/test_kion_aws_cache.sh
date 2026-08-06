#!/usr/bin/env bash
set -euo pipefail

root="$(pwd)/.test-kion-aws-cache-$$"
trap 'rm -rf "$root"' EXIT
fixture_bin="$root/home/.nix-profile/bin"

mkdir -p "$fixture_bin" "$root/home/.local/bin" "$root/home/.local/lib" "$root/home/.cache/kion-aws-cache"
cp chezmoi/dot_local/lib/kion-aws-cache "$root/home/.local/lib/kion-aws-cache"
cp chezmoi/dot_local/bin/executable_kac "$root/home/.local/bin/kac"

printf stale-access >"$root/home/.cache/kion-aws-cache/AWS_ACCESS_KEY_ID"
printf stale-secret >"$root/home/.cache/kion-aws-cache/AWS_SECRET_ACCESS_KEY"
printf stale-token >"$root/home/.cache/kion-aws-cache/AWS_SESSION_TOKEN"

cat >"$fixture_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ "${AWS_ACCESS_KEY_ID:-}" == fixture-access &&
	"${AWS_SECRET_ACCESS_KEY:-}" == fixture-secret &&
	"${AWS_SESSION_TOKEN:-}" == fixture-token ]]; then
	exit 0
fi
exit 1
EOF

cat >"$fixture_bin/kion-aws-refresh" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$HOME/.cache/kion-aws-cache"
printf fixture-access >"$HOME/.cache/kion-aws-cache/AWS_ACCESS_KEY_ID"
printf fixture-secret >"$HOME/.cache/kion-aws-cache/AWS_SECRET_ACCESS_KEY"
printf fixture-token >"$HOME/.cache/kion-aws-cache/AWS_SESSION_TOKEN"
EOF

cat >"$fixture_bin/gkion" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

chmod 700 "$fixture_bin/"*

HOME="$root/home" \
PATH="$fixture_bin:$PATH" \
AWS_ACCESS_KEY_ID=stale-access \
AWS_SECRET_ACCESS_KEY=stale-secret \
AWS_SESSION_TOKEN=stale-token \
bash -c 'source "$HOME/.local/bin/kac" ensure; test "$AWS_ACCESS_KEY_ID" = fixture-access'
