# pi-rust-airgapped

Airgapped distribution tooling for the pi-rust stack. This repo ships **no
binaries, no models, no code of the stack itself** — only the scripts that
assemble and install a self-contained offline bundle:

```
pi-rust-airgapped-llamafile-lfm3-1.7b-x86_64-rpi0.12.13.tar.gz  a llamafile distro
├── rpi                      # static musl binary (plain upstream pi-rust, renamed file)
├── pi-embedded-ai/            # the extension package (TS + lifecycle, no weights)
├── models/                  # .llamafile weights (from awesome-llamafiles)
├── SHA256SUMS               # integrity of everything above
├── install.sh               # offline installer
└── README.md                # this file (copy)

pi-rust-airgapped-cortiq-lfm3-1.7b-x86_64-rpi0.12.13.tar.gz    an LFM/cortiq distro
├── rpi                      # same host binary
├── cortiq-cpu               # CPU-only cortiq engine (static)
├── pi-embedded-ai/            # same extension
├── models/                  # .cmf models
├── SHA256SUMS
├── install.sh
└── README.md
```

**Naming.** Tag: `bundle-v<rpi>-<rev>` — one release per bundle revision. Archive:
`pi-rust-airgapped-<kind>-<model>-<arch>-rpi<rpi>.tar.gz`, one archive per model and
technology; `<arch>` is `uname -m` verbatim because every binary inside is
host-specific, and a bundled `ARCH` file makes `install.sh` refuse a cross-arch
install.

**One bundle, one technology.** A llamafile distro and a cortiq distro are separate
artifacts: mixing `--models-dir` with `--cortiq-bin` is refused by the build, and
each installer only acts on what its bundle carries.

Build time needs the inputs (network for a release download, or local paths
for a fully offline build). **Install time is 100% offline** — and so is
everything after: the model runs locally, no API keys, no telemetry.

## The three upstream inputs

| Input | Default source | Fully-offline alternative |
|-------|----------------|---------------------------|
| `rpi` binary | Upstream `yannelli/pi-rust` release (`--version`, vanilla binary renamed at bundle time) | `--rpi-bin /path/to/rpi` (local musl build) |
| `pi-embedded-ai/` | `../pi-embedded-ai` checkout | `--extension-dir` |
| llamafile distro: models | `../awesome-llamafiles` checkout, or `--models-release <tag>` | `--models-dir` |
| cortiq distro: engine | — | `--cortiq-bin /path/to/cortiq` |
| cortiq distro: models | — | `--cmf-dir /path/to/cmf-models` |

## New host from zero (no local checkouts needed)

Everything the installer needs travels inside one tarball, published as a
release asset on this repo. On the new host (one download, then offline):

```sh
# repos are public: anonymous download works, `gh` optional
gh release download bundle-v0.12.13-4 --repo andrea-tomassi/pi-rust-airgapped --pattern '*x86_64*.tar.gz'
# or without gh:
# curl -fsSL -O https://github.com/andrea-tomassi/pi-rust-airgapped/releases/download/bundle-v0.12.13-4/pi-rust-airgapped-cortiq-lfm3-1.7b-x86_64-rpi0.12.13.tar.gz
tar -xzf pi-rust-airgapped-*.tar.gz
cd pi-rust-airgapped-*
./install.sh --name rpi --check   # checksum → binary → extension → models → live proof
```

What comes from where: the `rpi` binary is the vanilla upstream release
(renamed at bundle time, never patched); the extension is `pi-embedded-ai`
at the bundled revision; the weights come from the `awesome-llamafiles`
`models-v1` release. No repo checkout is needed on the target host — only on
the machine that runs `make-bundle.sh`.

## Build a bundle

# llamafile distro
./scripts/make-bundle.sh --version v0.12.14
# fully offline build:
./scripts/make-bundle.sh --rpi-bin /path/to/rpi --extension-dir ../pi-embedded-ai --models-dir ../awesome-llamafiles
# models from the published distro (needs `gh` auth, no local checkout):
./scripts/make-bundle.sh --rpi-bin /path/to/rpi --models-release models-v1
# cortiq (LFM) distro: CMF models served by the bundled engine, no llamafile at all
./scripts/make-bundle.sh --rpi-bin /path/to/rpi \
  --cortiq-bin /path/to/cortiq-cpu --cmf-dir /path/to/cmf-models
```

## The cortiq engine (LFM distributions)

`.cmf` files are served by [cortiq](https://github.com/infosave2007/cmf), a
single Rust binary — no Python, no ML framework. The bundle carries a
**CPU-only** build installed as `cortiq-cpu`; the extension discovers that name
on `PATH` and serves the `.cmf` models through it (`/cortiq start`).

Build the engine for the bundle on any x86_64 Linux box with Rust installed:

```sh
rustup target add x86_64-unknown-linux-musl
apt-get install -y musl-tools          # musl-gcc
cargo install cortiq-cli --locked --no-default-features \
  --target x86_64-unknown-linux-musl --root /tmp/cortiq-out
cp /tmp/cortiq-out/bin/cortiq /path/to/cortiq-cpu
```

`--no-default-features` drops the GPU backends (`gpu`, `cuda`), which is what
makes the binary portable: it runs on any card-less host, and the shipped file
is statically linked. A CUDA build is worth it only when the target host has the
NVIDIA libraries — that is a different bundle, not this one.

Models: any `.cmf` file works. For LFM3-1.7B the smallest usable one is
`lfm3-1.7b-q4tp.cmf` (0.86 GB, `infosave/LFM3-1.7B-cmf`).

## Install a bundle (offline)

Carry the tarball to the target host (USB, scp, artifact store — any transport),
then:

```sh
tar -xzf pi-rust-airgapped-<date>.tar.gz
cd pi-rust-airgapped-<date>
./install.sh                    # installs `rpi` to ~/.local/bin
./install.sh --name my-pi       # custom executable name (never `pi`: the TypeScript pi owns that)
./install.sh --check            # also boots the server and lists models (~1 min, needs the weights)
```

What install does, in order:

1. verifies `SHA256SUMS` (aborts on any mismatch);
2. copies `rpi` to `$PREFIX/$NAME` (`~/.local/bin/rpi` by default);
3. copies `cortiq-cpu` to `$PREFIX/cortiq-cpu` when the bundle carries it;
4. registers the extension: copies `pi-embedded-ai/` to
   `~/.pi/agent/extensions/pi-embedded-ai` and registers that absolute path
   (a path into the extracted tarball would break once it is removed);
5. copies `models/*.llamafile` and `models/*.cmf` to `~/.pi/agent/models/` (skipped with `--skip-models`);
6. with `--check`: starts the stack once and prints `--list-models` (proves the
   model serves before you need it).

Re-running `install.sh` is the upgrade path: it replaces the binary,
re-installs the extension, and refreshes the models. The TypeScript `pi`
(`~/.pi/agent/bin/pi`, its npm packages, settings, auth) is never touched —
verified by the coexistence tests, only new files are created.

## Layout

```
scripts/
  make-bundle.sh   assemble the tarball from the three inputs
  install.sh       offline installer (checksum → binary → extension → models)
```
