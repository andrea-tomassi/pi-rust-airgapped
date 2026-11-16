# pi-rust-airgapped

Self-contained, offline bundles for the pi-rust stack: **one archive per model
and technology**, weights included. The repo ships only the scripts that
assemble and install them — the archives travel as release assets.

```
pi-rust-airgapped-<kind>-<model>-<arch>-rpi<rpi>.tar.gz
├── rpi               # vanilla upstream pi-rust binary, renamed (never patched)
├── pi-embedded-ai/   # the extension package (TS + lifecycle, no weights)
├── cortiq-cpu        # (cortiq archives only) the .cmf engine
├── models/           # the weights: one .llamafile, or the .cmf file(s)
├── ARCH              # host architecture; install.sh refuses a cross-arch install
├── SHA256SUMS        # integrity of everything above
├── install.sh        # offline installer
└── README.md         # copy of this file
```

**Naming.** Tag `bundle-v<rpi>-<rev>`: one release per bundle revision, holding
every archive of that revision. Archive
`pi-rust-airgapped-<kind>-<model>-<arch>-rpi<rpi>.tar.gz`: `<kind>` is
`llamafile` or `cortiq`; `<model>` is the model file stem with the quant
(`lfm3-1.7b-q4tp`, `lfm3-1.7b-q8_2f`); `<arch>` is `uname -m` verbatim because
the binaries are host-specific. One technology per archive: a llamafile distro
and a cortiq distro are never mixed.

**Current release:** [bundle-v0.12.14-1](https://github.com/andrea-tomassi/pi-rust-airgapped/releases/latest)
— extension pi-embedded-ai 0.3.1, cortiq-cpu 0.9.2 (with the reasoning_content
fix), models from [infosave/LFM3-1.7B-cmf](https://huggingface.co/infosave/LFM3-1.7B-cmf)
and [awesome-llamafiles models-v1](https://github.com/andrea-tomassi/awesome-llamafiles/releases/tag/models-v1).

## New host from zero

One download, then everything is offline:

```sh
gh release download --repo andrea-tomassi/pi-rust-airgapped --pattern '*x86_64*.tar.gz'
mkdir lfm && tar -xzf pi-rust-airgapped-*.tar.gz -C lfm && cd lfm
./install.sh --name rpi --check
```

`--check` verifies checksums, installs, then boots the stack once and lists
models — proof the model serves before you need it. No Node.js, no API keys,
no telemetry on the target host.

## What install.sh does, in order

1. verifies `SHA256SUMS` (aborts on any mismatch) and the `ARCH` marker;
2. copies `rpi` to `~/.local/bin/rpi` (`--name` renames it; never `pi` — the
   TypeScript pi owns that name);
3. copies `cortiq-cpu` next to it when the bundle carries one;
4. installs the extension to `~/.pi/agent/extensions/pi-embedded-ai` (absolute
   path, registered in settings);
5. copies the weights to `~/.pi/agent/models/` (`--skip-models` skips this);
6. with `--check`: boots and proves the stack.

Re-running it is the upgrade path: binary, extension and models are replaced;
the TypeScript pi and its settings are never touched.

## Using the bundle

`rpi` and the TypeScript `pi` coexist on the same host and share `~/.pi/agent`.
The extension commands are `/embedded-llama` (llamafile archives) and
`/embedded-cortiq` (cortiq archives); `set <model>` starts and uses a model —
TAB completes the names. Starting one engine stops the other.

## Build a bundle

Inputs: the `rpi` release (downloaded from upstream, or `--rpi-bin` for a
fully offline build), the extension checkout (default `../pi-embedded-ai`),
and the weights (GitHub release, Hugging Face, or a local dir).

```sh
# llamafile distro — weights from the awesome-llamafiles release (needs gh auth)
./scripts/make-bundle.sh --version v0.12.14 --models-release models-v1

# cortiq distro — .cmf from Hugging Face, verified against the repo's .sha256
./scripts/make-bundle.sh --version v0.12.14 \
  --cortiq-bin /path/to/cortiq-cpu \
  --cmf-release infosave/LFM3-1.7B-cmf --cmf-pattern q4tp

# fully offline build — every input is a local path
./scripts/make-bundle.sh --rpi-bin /path/to/rpi --extension-dir ../pi-embedded-ai \
  --cortiq-bin /path/to/cortiq-cpu --cmf-dir /path/to/cmf-models
```

`--cmf-pattern` picks one file from a multi-quant HF repo (one archive per
model keeps every asset under GitHub's 2 GB file limit).

## The cortiq engine

`.cmf` files are served by [cortiq](https://github.com/infosave2007/cmf): one
Rust binary, no Python, no ML framework. The bundle installs it as
`cortiq-cpu`; the extension finds that name on `PATH`.

Until [our reasoning_content fix](https://github.com/infosave2007/cmf/pull/163)
is merged upstream, build the engine from the
[fork](https://github.com/andrea-tomassi/cmf) (`cargo build --release -p
cortiq-cli`). The CPU-only CLI build is currently broken upstream
(`hotmix.rs` references the GPU-gated `moegptq` module) — the default-features
build falls back to CPU at runtime on hosts without a GPU.
