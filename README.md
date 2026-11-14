# pi-rust-airgapped

Airgapped distribution tooling for the pi-rust stack. This repo ships **no
binaries, no models, no code of the stack itself** — only the scripts that
assemble and install a self-contained offline bundle:

```
pi-rust-airgapped-<date>.tar.gz
├── rpi                      # static musl binary (plain upstream pi-rust, renamed file)
├── pi-embedded-ai/            # the extension package (TS + lifecycle, no weights)
├── models/                  # .llamafile weights (from awesome-llamafiles)
├── SHA256SUMS               # integrity of everything above
├── install.sh               # offline installer
└── README.md                # this file (copy)
```

Build time needs the inputs (network for a release download, or local paths
for a fully offline build). **Install time is 100% offline** — and so is
everything after: the model runs locally, no API keys, no telemetry.

## The three upstream inputs

| Input | Default source | Fully-offline alternative |
|-------|----------------|---------------------------|
| `rpi` binary | GitHub release of `andrea-tomassi/pi-rust` (`--version`) | `--rpi-bin /path/to/rpi` (local musl build) |
| `pi-embedded-ai/` | `../pi-embedded-ai` checkout | `--extension-dir` |
| `models/` | `../awesome-llamafiles` checkout, or `--models-release <tag>` (downloaded from the awesome-llamafiles releases) | `--models-dir` |

## Build a bundle

```sh
./scripts/make-bundle.sh --version v0.12.14
# fully offline build:
./scripts/make-bundle.sh --rpi-bin /path/to/rpi --extension-dir ../pi-embedded-ai --models-dir ../awesome-llamafiles
# models from the published distro (needs `gh` auth, no local checkout):
./scripts/make-bundle.sh --rpi-bin /path/to/rpi --models-release models-v1
```

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
3. registers the extension: `$NAME install ./pi-embedded-ai/` (local path, no network);
4. copies `models/*.llamafile` to `~/.pi/agent/models/` (skipped with `--skip-models`);
5. with `--check`: starts the stack once and prints `--list-models` (proves the
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
