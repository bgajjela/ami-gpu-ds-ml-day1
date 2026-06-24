This product includes Ubuntu 22.04 LTS and various open-source components
distributed under their respective licenses. You are purchasing packaging,
configuration, hardening, and support services only.

## Key components and sources

| Component | Source | License |
|---|---|---|
| Ubuntu 22.04 LTS | Canonical apt archive | Various (GPL, LGPL, MIT, Apache 2.0) |
| Nixpkgs nixos-25.05 | github.com/NixOS/nixpkgs | MIT |
| Python 3.11 / 3.12 / 3.13 | Nixpkgs nixos-25.05 | PSF License |
| PyTorch (CPU) | download.pytorch.org/whl/cpu | BSD-3-Clause |
| TensorFlow CPU | PyPI | Apache 2.0 |
| Transformers / Tokenizers | PyPI (Hugging Face) | Apache 2.0 |
| XGBoost | PyPI | Apache 2.0 |
| LightGBM | PyPI | MIT |
| MLflow | PyPI | Apache 2.0 |
| NumPy / SciPy / Pandas / scikit-learn | PyPI | BSD-3-Clause |
| Apache Spark | Nixpkgs nixos-25.05 | Apache 2.0 |
| OpenJDK 21 (Temurin) | Nixpkgs nixos-25.05 | GPL-2.0-with-classpath-exception |
| Julia | Nixpkgs nixos-25.05 | MIT |
| R | Nixpkgs nixos-25.05 | GPL-2.0 |
| Go toolchain | Nixpkgs nixos-25.05 | BSD-3-Clause |
| Rust / Cargo | Nixpkgs nixos-25.05 | MIT / Apache 2.0 |
| Node.js | Nixpkgs nixos-25.05 | MIT |
| AWS CLI v2 | awscli.amazonaws.com | Apache 2.0 |
| Trivy | github.com/aquasecurity/trivy | Apache 2.0 |
| OpenSCAP | Ubuntu apt | LGPL-2.1 |

## On a running instance — enumerate all licenses

```bash
# All pip-installed packages with versions
cat /usr/share/BUILD_INFO/packages.txt

# CycloneDX SBOM (JSON)
cat /usr/share/BUILD_INFO/sbom.cyclonedx.json

# All Nix derivation closures
nix path-info --recursive /opt/nix/envs/base
nix path-info --recursive /opt/nix/envs/pro    # pro AMI only

# Individual package license metadata (Nix)
nix-store --query --requisites /opt/nix/envs/base | xargs -I{} cat {}/share/licenses 2>/dev/null || true
```

## Notes

- No ownership of third-party intellectual property is claimed.
- All trademarks (PyTorch, TensorFlow, Spark, etc.) are the property of
  their respective owners.
- Open-source licenses are not affected by the AWS Standard Contract that
  governs this Marketplace listing. Each open-source component retains its
  upstream license terms.

