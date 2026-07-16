# SEAPATH Yocto BSP Agent Notes

## Workspace Boundaries

- This checkout is assembled by Google `repo`; each directory under `sources/` is a separate Git repository and `sources/` is ignored by this repository. Run Git commands and commit layer changes from the relevant source directory, not from this root.
- For changes in the project-owned layer, also follow [`sources/meta-seapath/AGENTS.md`](sources/meta-seapath/AGENTS.md).
- `build/`, `seapath.conf`, `keys/*`, `patches/*.done`, and `release-files/` are local/generated state. Do not treat them as source or overwrite a developer's configuration.

## Setup And Builds

- Populate sources with `repo init -u https://github.com/seapath/repo-manifest.git && repo sync` when `.repo/`/`sources/` are absent.
- Before building, create `seapath.conf` from `seapath.conf.sample` and provide `keys/ansible_public_ssh_key.pub`. CI only `touch`es the key, but deployment needs a real public key.
- CQFD is the supported build environment: run `cqfd init` after `.cqfd/docker/Dockerfile` changes, inspect current targets with `cqfd flavors`, then build one target with `cqfd -b <flavor>`. `.cqfdrc`, not the README's abbreviated list, is authoritative.
- Prefer the narrow matching flavor: `host_efi`, `host_standalone_efi`, `guest_efi`, `flasher`, or `observer_efi`. `all`, `sfl_ci`, and `release` build multiple images; an initial full build takes roughly 4-5 hours and 50 GB.
- Direct/focused syntax is `./build.sh -i <image> --distro <distro> --machine <machine> -- <bitbake command>`. The defaults are host image/distro/machine; do not rely on them for guest, flasher, or observer work.
- There is no fast root lint/unit-test suite. Validate metadata or recipe changes with the smallest compatible BitBake parse/task/image build; CI builds host, standalone host, guest, and observer images and then performs CVE analysis.

## Build Gotchas

- Normal `build.sh` runs delete and regenerate `build/conf/bblayers.conf` by discovering layers and applying `layers.blocklist`; manual edits there do not persist. Use `--no-layers-update` only when intentionally preserving it.
- `build.sh -r`/`--remove-build-dir` deletes all of `build/`. Do not use it for routine focused verification. Reuse external `DL_DIR`/`SSTATE_DIR` mounts as documented in `README.adoc` for expensive builds.
- Keep `SEAPATH_SECCOMPILE_MANIFEST_SKIP=1` for ordinary iteration unless validating compilation hardening; enabling that manifest costs more than an hour.
- Root `patches/*.patch` modify fetched source repositories at build start. Their ignored `.done` markers are the idempotency mechanism; account for both the patch and the target source state when debugging.
- Build products and security/SBOM reports are under `build/tmp/deploy/images/<machine>/` and `build/security/`, never under the layer repository.
