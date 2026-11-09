# Assertions for the zsh test scripts. Source it; do not execute it.

fail() {
	print -ru2 -- "FAIL: $*"
	exit 1
}

assert_contains() {
	[[ $1 == *"$2"* ]] || fail "expected output to contain: $2"
}

assert_not_contains() {
	[[ $1 != *"$2"* ]] || fail "expected output not to contain: $2"
}

assert_file_contains() {
	rg -Fq -- "$2" "$1" || fail "expected $1 to contain: $2"
}

assert_eq() {
	[[ $1 == "$2" ]] || fail "expected [$2], got [$1]"
}

# PATH that resolves bash and zsh the way an agent shell on macOS does: the system
# /bin/bash (3.2) and /bin/zsh (5.9) first. A helper run through its shebang then
# fails here exactly as it does for an agent. On Linux, where /bin/bash is bash 5,
# the PATH is effectively unchanged.
system_shell_path() {
	local shim=$1
	mkdir -p -- $shim
	[[ -x /bin/bash ]] && ln -sf /bin/bash $shim/bash
	[[ -x /bin/zsh ]] && ln -sf /bin/zsh $shim/zsh
	print -r -- "$shim:$PATH"
}
