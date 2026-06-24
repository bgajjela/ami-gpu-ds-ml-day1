# Governance

## Project roles

| Role | Who | Responsibilities |
|------|-----|-----------------|
| Maintainer | [@bgajjela](https://github.com/bgajjela) | Reviews and merges PRs, cuts releases, responds to security disclosures, manages CI and branch protection |
| Contributor | Anyone | Opens issues, submits pull requests, reports bugs or CIS control gaps |

## Decision making

This is a solo-maintained project. The maintainer has final say on all decisions including:

- Accepting or rejecting contributions
- Release timing and versioning
- Changes to hardening controls or toolchain versions
- Security disclosures and CVE remediation

For significant changes (new architectures, major dependency updates, hardening policy changes), the maintainer will open a GitHub Discussion or issue before merging to allow community input.

## Contributions

All contributions are subject to the process described in [CONTRIBUTING.md](CONTRIBUTING.md), including DCO sign-off on all commits.

## Releases

Releases follow [Semantic Versioning](https://semver.org/). All releases are GPG-signed by the maintainer. Release notes are documented in [CHANGELOG.md](CHANGELOG.md).

## Access continuity

The maintainer keeps repository admin credentials and GPG private key in a secure password manager with emergency access instructions held by a trusted contact. In the event the maintainer is unavailable for more than 30 days, contributors may open a GitHub issue requesting access transfer. The project is Apache 2.0 licensed, allowing any fork to continue independently.

## Code of conduct

All participants are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
