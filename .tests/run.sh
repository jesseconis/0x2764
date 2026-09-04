#!/usr/bin/env bash
set -Eeuo pipefail

project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
repo=$tmp/repo
home=$tmp/home
mkdir -p "$repo" "$home/.config/nvim" "$home/.config/conflict" "$home/.local/bin"
cp "$project/0x2764" "$repo/0x2764"
printf '# packages\n' > "$repo/.0x2764-packages"
printf 'set number\n' > "$home/.config/nvim/init.vim"
printf 'source\n' > "$home/.config/conflict/value"
printf '[user]\n' > "$home/.gitconfig"
chmod +x "$repo/0x2764"

run() { HOME=$home XDG_CONFIG_HOME=$home/.config "$repo/0x2764" "$@"; }
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

out=$(run import --dry-run nvim)
[[ $out == *"$repo/nvim/.config/nvim"* ]] || fail 'dry run did not show destination'
[[ -d $home/.config/nvim && ! -e $repo/nvim ]] || fail 'dry run changed files'

out=$(run import --yes nvim 2>&1)
[[ $out == *'Preflight passed; creating links...'* ]] || fail 'successful preflight was not clearly reported'
[[ $out != *'in simulation mode so not modifying filesystem'* ]] || fail 'internal simulation warning leaked into output'
[[ -f $repo/nvim/.config/nvim/init.vim ]] || fail 'config was not moved'
[[ -L $home/.config/nvim ]] || fail 'config was not stowed'
grep -Fqx nvim "$repo/.0x2764-packages" || fail 'package was not registered'

run unstow nvim >/dev/null
[[ ! -e $home/.config/nvim ]] || fail 'unstow left target behind'
run stow nvim >/dev/null
[[ -L $home/.config/nvim ]] || fail 'restow did not restore target'

out=$(run check nvim)
[[ $out == *'All package links are healthy.'* ]] || fail 'check did not report healthy links'

rm -- "$home/.config/nvim"
if out=$(run check nvim 2>&1); then
    fail 'check succeeded with a missing link'
fi
[[ $out == *'MISSING '*'.config/nvim [nvim]'* ]] || fail 'check did not find a missing link'
out=$(run doctor --repair --yes nvim)
[[ $out == *'Repair complete.'* && -L $home/.config/nvim ]] || fail 'doctor did not repair a missing link'

rm -- "$home/.config/nvim"
ln -s ../old-repository/nvim "$home/.config/nvim"
if out=$(run doctor nvim 2>&1); then
    fail 'doctor succeeded with an unrepaired broken link'
fi
[[ $out == *'BROKEN '*'.config/nvim [nvim]'* ]] || fail 'doctor did not find a broken link'
run check --fix --yes nvim >/dev/null
[[ -L $home/.config/nvim ]] || fail 'check --fix did not recreate a broken link'
[[ $(realpath "$home/.config/nvim") == "$repo/nvim/.config/nvim" ]] || fail 'repaired link points to the wrong package'

run add --yes git "$home/.gitconfig" >/dev/null
[[ -f $repo/git/.gitconfig && -L $home/.gitconfig ]] || fail 'home file import failed'

# A failed Stow simulation must restore the source and remove the package.
mkdir -p "$home/conflict-source"
printf 'data\n' > "$home/conflict-source/value"
cat > "$tmp/failing-stow" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    [[ $arg == --simulate ]] && exit 1
done
exec stow "$@"
EOF
chmod +x "$tmp/failing-stow"
export STOW_BIN=$tmp/failing-stow
if run add --yes rollback "$home/conflict-source/value" >/dev/null 2>&1; then
    fail 'import with failed simulation unexpectedly succeeded'
fi
unset STOW_BIN
[[ -f $home/conflict-source/value ]] || fail 'failed import was not restored'
[[ ! -e $repo/rollback ]] || fail 'failed package was not removed'

printf 'All tests passed.\n'
