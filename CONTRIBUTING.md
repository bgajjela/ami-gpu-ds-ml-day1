# Contributing

Thanks for your interest in contributing. This project builds a CIS-hardened Ubuntu 22.04 AMI for ML/DS workloads on AWS.

## Ways to contribute

- **Bug reports** — open an issue with reproduction steps and the output of `sudo ami-scan`
- **CIS control gaps** — if you find a benchmark that isn't applied, open an issue referencing the control ID (e.g. `CIS 5.2.1`)
- **New toolchain support** — additional language runtimes or ML frameworks via Nix
- **ARM64 parity** — issues specific to Graviton3 builds
- **Documentation** — corrections to README, USAGE.md, or inline script comments

## Getting started

```bash
git clone https://github.com/bgajjela/aws-amis-ml.git
cd aws-amis-ml
cp vars.example.pkrvars.hcl my.pkrvars.hcl   # fill in subnet_id, security_group_id
```

**Prerequisites:** Packer ≥ 1.9, AWS credentials with EC2 + SSM permissions, ShellCheck.

## Making changes

1. Fork the repo and create a branch: `fix/cis-5-2-1` or `feat/add-rust-nightly`
2. Run ShellCheck before pushing:
   ```bash
   shellcheck -S warning harden.sh scripts/*.sh
   ```
3. Run the CIS compliance check:
   ```bash
   bash tests/cis-check.sh
   ```
4. Open a pull request against `main` — describe the control ID or use case your change addresses

## Coding standards

Primary language is Bash/shell. All shell scripts must comply with [ShellCheck](https://www.shellcheck.net/) at `-S warning` severity (the strictest practical level). ShellCheck enforces this automatically on every CI push.

General rules:
- Use `#!/usr/bin/env bash` shebangs
- Quote all variable expansions: `"${var}"` not `$var`
- Use `[[ ]]` for conditionals, not `[ ]`
- Prefer `$(command)` over backticks

## Hardening script conventions

- All `harden.sh` changes must reference the CIS benchmark control ID in a comment
- `sysctl` changes go in the sysctl block, not ad hoc inline
- Kernel module blacklists go in `/etc/modprobe.d/cis-blacklist.conf`

## Testing requirements

Any PR that adds major new functionality MUST include a corresponding test in `tests/cis-check.sh` or a new test script under `tests/`. Bug fixes MUST include a regression test where technically feasible.

## Reporting security vulnerabilities

Do not open a public issue. See [SECURITY.md](SECURITY.md) for the private disclosure process.

## Code review standards

All proposed changes MUST be submitted as a pull request against `main`. Direct pushes to `main` are blocked by branch protection.

**What reviewers check:**

- ShellCheck passes at `-S warning` — no new warnings introduced
- CIS compliance check (`bash tests/cis-check.sh`) passes — 0 FAIL
- Any new hardening control references the CIS benchmark control ID in a comment
- No secrets, credentials, or AWS account IDs introduced
- SPDX license header present on any new source files
- DCO `Signed-off-by` present on all commits

**Acceptance criteria:**

- CI must pass (ShellCheck + CIS check + Trivy + Packer validate + Checkov)
- At least one approving review required before merge
- Changes to `harden.sh` must explain which CIS control is being added or modified

**Review process:**

The maintainer reviews all PRs. For security-sensitive changes (hardening controls, CI pipeline, dependency updates), a detailed explanation of the change and its security impact is required in the PR description.

## Developer Certificate of Origin (DCO)

All contributions must be signed off to certify that you wrote the contribution or have the right to submit it under the project license. Add a `Signed-off-by` line to every commit:

```bash
git commit -s -m "your commit message"
```

This adds:
```
Signed-off-by: Your Name <your@email.com>
```

By signing off you agree to the [Developer Certificate of Origin v1.1](https://developercertificate.org/).

## License

By contributing you agree your changes are licensed under [Apache 2.0](LICENSE).
