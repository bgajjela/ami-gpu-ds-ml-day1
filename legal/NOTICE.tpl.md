# OSS Notices

This AMI bundles open-source software installed via Ubuntu and Nix, plus the
NVIDIA driver and CUDA toolkit. Open-source components remain under their
respective upstream licenses; NVIDIA components are under the NVIDIA CUDA Toolkit
EULA. This distribution provides integration, configuration, and support services only.

## Sources

- Ubuntu 22.04 LTS (Canonical) — apt archive packages
- NVIDIA driver (570) + CUDA 12.8 — developer.download.nvidia.com (NVIDIA CUDA Toolkit EULA)
- Nixpkgs nixos-25.05 channel — Python runtimes and ML libraries
- PyTorch CUDA wheels (cu128) — download.pytorch.org (bundle NVIDIA CUDA runtime/cuDNN)
- AWS CLI v2 — AWS official installer (Apache 2.0)

## On a running instance

List all Python packages and versions:

```bash
cat /usr/share/BUILD_INFO/packages.txt
```

Enumerate Nix derivations (base env):

```bash
nix path-info --recursive /opt/nix/envs/base
```

Enumerate Nix derivations (pro env):

```bash
nix path-info --recursive /opt/nix/envs/pro
```

Show Nix flake outputs:

```bash
nix flake show /opt/nix/flake
```

## License terms

Subscriber license terms are at `/usr/share/BUILD_INFO/EULA.txt` on each instance.

Trademarks are the property of their respective owners.
