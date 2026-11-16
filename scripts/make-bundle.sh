#!/bin/sh
# Assemble an airgapped bundle: rpi binary + pi-embedded-ai extension + models.
# Usage: make-bundle.sh [--version vX.Y.Z | --rpi-bin PATH] [--extension-dir D]
#                        [--models-dir D | --models-release TAG]
#                        [--cortiq-bin PATH] [--cmf-dir D | --cmf-release HF_REPO [--cmf-pattern PAT]]
#                        [--model-id ID] [--name rpi] [--out DIR]
# The archive is arch-specific: pi-rust-airgapped-<kind>-<model>-<arch>-rpi<ver>.tar.gz
# A --version build downloads the static musl binary from the fork's releases
# (needs network at BUILD time). A --rpi-bin build is fully offline.
# Models come from --models-dir (local checkout) or --models-release TAG
# (downloaded from the awesome-llamafiles releases; needs `gh` auth).
# --cortiq-bin adds the CPU-only cortiq engine (installed as `cortiq-cpu`) and
# --cmf-dir / --cmf-release its `.cmf` model files (an LFM distribution);
# --cmf-release downloads the models from a Hugging Face repo at build time and
# verifies them against the repo's own `.sha256` sidecars. A bundle needs at
# least one model of either kind.
set -eu

REPO_URL=https://github.com/yannelli/pi-rust
TARGET=x86_64-unknown-linux-musl
arch=$(uname -m)

say() { printf '%s\n' "$*"; }
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

version=
rpi_bin=
extension_dir=
models_dir=
models_release=
cortiq_bin=
cmf_release=
cmf_pattern=
model_id=${model_id:-lfm3-1.7b}
cmf_dir=
name=rpi
out=.

while [ $# -gt 0 ]; do
	case "$1" in
	--version) version=${2:?--version needs a value}; shift 2 ;;
	--rpi-bin) rpi_bin=${2:?--rpi-bin needs a value}; shift 2 ;;
	--extension-dir) extension_dir=${2:?--extension-dir needs a value}; shift 2 ;;
	--models-dir) models_dir=${2:?--models-dir needs a value}; shift 2 ;;
	--models-release) models_release=${2:?--models-release needs a value}; shift 2 ;;
	--cortiq-bin) cortiq_bin=${2:?--cortiq-bin needs a value}; shift 2 ;;
	--cmf-release) cmf_release=${2:?--cmf-release needs a value}; shift 2 ;;
	--cmf-pattern) cmf_pattern=${2:?--cmf-pattern needs a value}; shift 2 ;;
	--model-id) model_id=${2:?--model-id needs a value}; shift 2 ;;
	--cmf-dir) cmf_dir=${2:?--cmf-dir needs a value}; shift 2 ;;
	--name) name=${2:?--name needs a value}; shift 2 ;;
	--out) out=${2:?--out needs a value}; shift 2 ;;
	-h | --help) sed -n '2,11p' "$0"; exit 0 ;;
	*) die "unknown flag $1" ;;
	esac
done

[ -n "$rpi_bin" ] || [ -n "$version" ] || die "need --version vX.Y.Z or --rpi-bin PATH"
[ -z "$rpi_bin" ] || [ -z "$version" ] || die "--version and --rpi-bin are mutually exclusive"
[ "$name" != pi ] || die "the installed name must not be 'pi': the TypeScript pi owns that"

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
extension_dir=${extension_dir:-$root/../pi-embedded-ai}
[ -d "$extension_dir" ] || die "extension dir not found: $extension_dir"
[ -f "$extension_dir/package.json" ] || die "not an extension package: $extension_dir (no package.json)"

# One bundle, one technology: a llamafile distro and a cortiq distro are separate artifacts,
# so mixing the two inputs is refused instead of silently producing a hybrid.
if [ -n "$cortiq_bin" ]; then
	kind=cortiq
	[ -z "${models_dir:-}" ] || die "--models-dir belongs to a llamafile bundle: a cortiq bundle takes --cmf-dir/--cmf-release"
	[ -z "${models_release:-}" ] || die "--models-release belongs to a llamafile bundle: a cortiq bundle takes --cmf-dir/--cmf-release"
else
	kind=llamafile
	[ -z "$cmf_dir" ] || die "--cmf-dir needs --cortiq-bin: a CMF model without its engine is not a bundle"
fi

if [ "$kind" = cortiq ]; then
	[ -x "$cortiq_bin" ] || die "not executable: $cortiq_bin"
	[ -n "$cmf_dir" ] || [ -n "$cmf_release" ] || die "a cortiq bundle needs --cmf-dir or --cmf-release with at least one .cmf"
	[ -z "$cmf_dir" ] || [ -d "$cmf_dir" ] || die "cmf dir not found: $cmf_dir"
else
	if [ -n "${models_release:-}" ]; then
		[ -z "${models_dir:-}" ] || die "--models-dir and --models-release are mutually exclusive"
	else
		models_dir=${models_dir:-$root/../awesome-llamafiles}
	fi
	[ -n "${models_release:-}" ] || [ -d "$models_dir" ] || die "models dir not found: $models_dir"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

# 1. The binary.
if [ -n "$rpi_bin" ]; then
	[ -x "$rpi_bin" ] || die "not executable: $rpi_bin"
	cp "$rpi_bin" "$work/rpi"
else
	case "$arch" in
		x86_64) [ "$TARGET" = "x86_64-unknown-linux-musl" ] || die "no rpi release for $arch: pass --rpi-bin" ;;
		*) die "no rpi release for $arch: pass --rpi-bin" ;;
	esac
	tag="v${version#v}"
	url="$REPO_URL/releases/download/$tag/pi-$tag-$TARGET.tar.gz"
	say "downloading $url"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --retry 3 -o "$work/release.tar.gz" "$url" || die "download failed: $url"
	else
		wget -q -O "$work/release.tar.gz" "$url" || die "download failed: $url"
	fi
	tar -xzf "$work/release.tar.gz" -C "$work"
	cp "$work/pi-$tag-$TARGET/pi" "$work/rpi" || die "archive has no pi binary"
fi
chmod 755 "$work/rpi"

# 1b. The cortiq engine of a cortiq bundle, installed as `cortiq-cpu` (the extension looks
# for that name). A llamafile bundle carries no engine of its own.
if [ "$kind" = cortiq ]; then
	cp "$cortiq_bin" "$work/cortiq-cpu"
	chmod 755 "$work/cortiq-cpu"
	say "cortiq engine: $cortiq_bin -> cortiq-cpu ($(wc -c <"$work/cortiq-cpu" | tr -d ' ') bytes)"
fi

# 2. The extension (sources only: no node_modules, no .git).
mkdir -p "$work/pi-embedded-ai"
(
	cd "$extension_dir" && tar -cf - \
		--exclude='.git' --exclude='node_modules' --exclude='*.log' \
		package.json src README.md LICENSE
) | (cd "$work/pi-embedded-ai" && tar -xf -)
[ -f "$work/pi-embedded-ai/package.json" ] || die "extension packaging failed"

# 3. The models (weights travel as files, never in git of the extension).
mkdir -p "$work/models"
found=0
cmf=0
if [ "$kind" = llamafile ]; then
	if [ -n "${models_release:-}" ]; then
		command -v gh >/dev/null 2>&1 || die "--models-release needs 'gh' (authenticated: gh auth login)"
		models_dir="$work/models-dl"
		mkdir -p "$models_dir"
		say "downloading models $models_release from andrea-tomassi/awesome-llamafiles"
		gh release download "$models_release" --repo andrea-tomassi/awesome-llamafiles \
			--pattern '*.llamafile' --dir "$models_dir" || die "models download failed"
	fi
	for model in "$models_dir"/*.llamafile; do
		[ -e "$model" ] || continue
		cp "$model" "$work/models/"
		found=$((found + 1))
	done
	[ "$found" -gt 0 ] || die "no .llamafile in $models_dir"
	for doc in MODELS.md README.md LICENSE LICENSE.LFM3; do
		[ -f "$models_dir/$doc" ] && cp "$models_dir/$doc" "$work/models/"
	done
else
	if [ -n "$cmf_release" ]; then
		[ -z "$cmf_dir" ] || die "--cmf-dir and --cmf-release are mutually exclusive"
		cmf_dir="$work/cmf-dl"
		mkdir -p "$cmf_dir"
		say "downloading cmf models from huggingface.co/$cmf_release"
		repo_files=$(curl -fsSL --retry 3 "https://huggingface.co/api/models/$cmf_release" \
			| grep -o '"rfilename":"[^"]*"' | cut -d'"' -f4) || die "huggingface listing failed: $cmf_release"
		for name in $repo_files; do
			if [ -n "$cmf_pattern" ] && ! printf '%s\n' "$name" | grep -q -- "$cmf_pattern"; then
				continue
			fi
			case "$name" in
				*.cmf|*.cmf.sha256|README.md|LICENSE)
					curl -fsSL --retry 3 -o "$cmf_dir/$name" \
						"https://huggingface.co/$cmf_release/resolve/main/$name" \
						|| die "download failed: $name"
					;;
			esac
		done
		for sum in "$cmf_dir"/*.cmf.sha256; do
			[ -e "$sum" ] || continue
			(cd "$cmf_dir" && sha256sum -c "$(basename "$sum")") >/dev/null \
				|| die "sha256 mismatch: $sum"
			say "verified: $(basename "$sum")"
		done
	fi
	for model in "$cmf_dir"/*.cmf; do
		[ -e "$model" ] || continue
		cp "$model" "$work/models/"
		cmf=$((cmf + 1))
	done
	[ "$cmf" -gt 0 ] || die "no .cmf in $cmf_dir"
	for doc in README.md LICENSE LICENSE.LFM3; do
		[ -f "$cmf_dir/$doc" ] && cp "$cmf_dir/$doc" "$work/models/"
	done
fi
say "bundle: $kind ($found llamafile, $cmf cmf)"

# 4. Installer + docs + checksums. The ARCH marker lets install.sh refuse a
# cross-arch install: binaries in here are not portable.
cp "$root/scripts/install.sh" "$work/install.sh"
cp "$root/README.md" "$work/README.md"
printf '%s\n' "$arch" >"$work/ARCH"
payload="rpi pi-embedded-ai models install.sh README.md ARCH"
[ "$kind" = cortiq ] && payload="$payload cortiq-cpu"
(cd "$work" && find $payload -type f -exec sha256sum {} + | sort -k2 >SHA256SUMS)

bundle="pi-rust-airgapped-$kind-$model_id-$arch-rpi${version#v}.tar.gz"
mkdir -p "$out"
tar -czf "$out/$bundle" -C "$work" $payload SHA256SUMS
say "bundle: $out/$bundle ($(du -h "$out/$bundle" | cut -f1))"
say "contents:"; tar -tzf "$out/$bundle" | head -12
