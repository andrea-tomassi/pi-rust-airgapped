#!/bin/sh
# Offline installer for a pi-rust airgapped bundle. Run from the extracted bundle dir.
# Usage: install.sh [--name rpi] [--prefix ~/.local/bin] [--models] [--skip-models] [--check]
#   --name    executable file name (default: rpi; must not be 'pi')
#   --prefix  install directory (default: ~/.local/bin)
#   --models  copy models/*.llamafile to ~/.pi/agent/models/ (default: on)
#   --check   boot once and print --list-models (proves the model serves)
set -eu

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

name=rpi
prefix=
models=1
check=0

while [ $# -gt 0 ]; do
	case "$1" in
	--name) name=${2:?--name needs a value}; shift 2 ;;
	--prefix) prefix=${2:?--prefix needs a value}; shift 2 ;;
	--models) models=1; shift ;;
	--skip-models) models=0; shift ;;
	--check) check=1; shift ;;
	-h | --help) sed -n '2,8p' "$0"; exit 0 ;;
	*) die "unknown flag $1" ;;
	esac
done

[ "$name" != pi ] || die "refusing to install as 'pi': the TypeScript pi owns that name"
case "$name" in
*[!a-zA-Z0-9._-]*) die "unsafe name '$name': letters, digits, '.', '_' and '-' only" ;;
esac
[ -f ./rpi ] || die "run from the extracted bundle directory (./rpi missing)"
[ -f ./SHA256SUMS ] || die "SHA256SUMS missing: refusing to install an unverified bundle"

# 1. Verify integrity (offline: sha256sum of the bundle files).
if command -v sha256sum >/dev/null 2>&1; then
	sha256sum -c SHA256SUMS || die "checksum mismatch: bundle is corrupt or tampered with"
else
	shasum -a 256 -c SHA256SUMS || die "checksum mismatch: bundle is corrupt or tampered with"
fi
say "checksums ok"

# 2. Install the binary (a new file; nothing of the TypeScript pi is touched).
if [ -z "$prefix" ]; then
	[ -n "${HOME:-}" ] || die "HOME is not set; pass --prefix"
	prefix="$HOME/.local/bin"
fi
mkdir -p "$prefix" 2>/dev/null || die "could not create $prefix"
prefix=$(CDPATH='' cd -- "$prefix" && pwd)
[ -w "$prefix" ] || die "$prefix is not writable"
cp ./rpi "$prefix/$name.new" && chmod 755 "$prefix/$name.new" && mv -f "$prefix/$name.new" "$prefix/$name"
say "installed $prefix/$name"
"$prefix/$name" --version >/dev/null || die "$prefix/$name does not run on this host"

# 3. Register the extension from the local bundle path (no network).
[ -d ./pi-llamafile ] || die "./pi-llamafile missing"
"$prefix/$name" install ./pi-llamafile/ || die "extension install failed"
say "extension pi-llamafile registered"

# 4. Place the weights where the extension discovers them.
if [ "$models" -eq 1 ]; then
	[ -n "${HOME:-}" ] || die "HOME is not set; pass --skip-models or set HOME"
	dest="$HOME/.pi/agent/models"
	mkdir -p "$dest" || die "could not create $dest"
	n=0
	for model in ./models/*.llamafile; do
		[ -e "$model" ] || continue
		cp "$model" "$dest/"
		n=$((n + 1))
	done
	[ "$n" -gt 0 ] || warn "no .llamafile in ./models; place one in $dest or set PI_LLAMAFILE_DIR"
	say "models in $dest ($n files)"
fi

case ":${PATH:-}:" in
*":$prefix:"* | *":$prefix/"*) ;;
*) say "$prefix is not on your PATH. Add it, then open a new terminal." ;;
esac

if [ "$check" -eq 1 ]; then
	say "booting once to prove the model serves (this loads ~1 GB, takes about a minute)..."
	"$prefix/$name" --list-models
fi
say "done. Run: $name"
