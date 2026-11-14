#!/bin/sh
# Assemble an airgapped bundle: rpi binary + pi-llamafile extension + models.
# Usage: make-bundle.sh [--version vX.Y.Z | --rpi-bin PATH] [--extension-dir D]
#                        [--models-dir D] [--name rpi] [--out DIR]
# A --version build downloads the static musl binary from the fork's releases
# (needs network at BUILD time). A --rpi-bin build is fully offline.
set -eu

REPO_URL=https://github.com/andrea-tomassi/pi-rust
TARGET=x86_64-unknown-linux-musl

say() { printf '%s\n' "$*"; }
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

version=
rpi_bin=
extension_dir=
models_dir=
name=rpi
out=.

while [ $# -gt 0 ]; do
	case "$1" in
	--version) version=${2:?--version needs a value}; shift 2 ;;
	--rpi-bin) rpi_bin=${2:?--rpi-bin needs a value}; shift 2 ;;
	--extension-dir) extension_dir=${2:?--extension-dir needs a value}; shift 2 ;;
	--models-dir) models_dir=${2:?--models-dir needs a value}; shift 2 ;;
	--name) name=${2:?--name needs a value}; shift 2 ;;
	--out) out=${2:?--out needs a value}; shift 2 ;;
	-h | --help) sed -n '2,7p' "$0"; exit 0 ;;
	*) die "unknown flag $1" ;;
	esac
done

[ -n "$rpi_bin" ] || [ -n "$version" ] || die "need --version vX.Y.Z or --rpi-bin PATH"
[ -z "$rpi_bin" ] || [ -z "$version" ] || die "--version and --rpi-bin are mutually exclusive"
[ "$name" != pi ] || die "the installed name must not be 'pi': the TypeScript pi owns that"

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
extension_dir=${extension_dir:-$root/../pi-llamafile}
models_dir=${models_dir:-$root/../pi-llamafile-models}
[ -d "$extension_dir" ] || die "extension dir not found: $extension_dir"
[ -f "$extension_dir/package.json" ] || die "not an extension package: $extension_dir (no package.json)"
[ -d "$models_dir" ] || die "models dir not found: $models_dir"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

# 1. The binary.
if [ -n "$rpi_bin" ]; then
	[ -x "$rpi_bin" ] || die "not executable: $rpi_bin"
	cp "$rpi_bin" "$work/rpi"
else
	tag="v${version#v}"
	url="$REPO_URL/releases/download/$tag/pi-$tag-$TARGET.tar.gz"
	say "downloading $url"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --retry 3 -o "$work/release.tar.gz" "$url" || die "download failed: $url"
	else
		wget -q -O "$work/release.tar.gz" "$url" || die "download failed: $url"
	fi
	tar -xzf "$work/release.tar.gz" -C "$work"
	cp "$work/pi-$tag-$TARGET/rpi" "$work/rpi" || die "archive has no rpi binary"
fi
chmod 755 "$work/rpi"

# 2. The extension (sources only: no node_modules, no .git).
mkdir -p "$work/pi-llamafile"
(
	cd "$extension_dir" && tar -cf - \
		--exclude='.git' --exclude='node_modules' --exclude='*.log' \
		package.json src README.md LICENSE
) | (cd "$work/pi-llamafile" && tar -xf -)
[ -f "$work/pi-llamafile/package.json" ] || die "extension packaging failed"

# 3. The models (weights travel as files, never in git of the extension).
mkdir -p "$work/models"
found=0
for model in "$models_dir"/*.llamafile; do
	[ -e "$model" ] || continue
	cp "$model" "$work/models/"
	found=$((found + 1))
done
[ "$found" -gt 0 ] || die "no .llamafile in $models_dir"
for doc in MODELS.md README.md; do
	[ -f "$models_dir/$doc" ] && cp "$models_dir/$doc" "$work/models/"
done

# 4. Installer + docs + checksums.
cp "$root/scripts/install.sh" "$work/install.sh"
cp "$root/README.md" "$work/README.md"
(cd "$work" && find rpi pi-llamafile models install.sh README.md -type f -exec sha256sum {} + | sort -k2 >SHA256SUMS)

stamp=$(date +%Y%m%d)
bundle="pi-rust-airgapped-$stamp.tar.gz"
mkdir -p "$out"
tar -czf "$out/$bundle" -C "$work" rpi pi-llamafile models SHA256SUMS install.sh README.md
say "bundle: $out/$bundle ($(du -h "$out/$bundle" | cut -f1))"
say "contents:"; tar -tzf "$out/$bundle" | head -12
