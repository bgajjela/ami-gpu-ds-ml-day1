# Export Administration Regulations (EAR) Self-Classification Record

## Product
CPU DS/ML AMI (Base and Pro variants) — AWS Marketplace

## ECCN Determination

| Field | Value |
|---|---|
| **ECCN** | 5D002.c.1 |
| **Category** | 5 — Telecommunications and Information Security |
| **Product group** | D — Software |
| **Control parameter** | c.1 — Software designed or modified to use cryptography |
| **License exception** | ENC — Mass-market encryption (15 CFR 740.17(b)(1)) |
| **Jurisdiction** | EAR (not ITAR) |

## Basis for ENC Exception

This product qualifies for License Exception ENC under 15 CFR 740.17(b)(1) because:

1. **Publicly available**: all cryptographic components are publicly available
   from Ubuntu apt, PyPI, and GitHub — not custom or proprietary
2. **Mass-market**: components are widely distributed to the general public
   (OpenSSL, OpenSSH, Python cryptography, curl)
3. **Not military-grade**: no components designed for government or military
   intelligence use; no key escrow, no classified algorithms
4. **No custom crypto**: the AMI configures and hardens existing cryptographic
   software — it does not implement new cryptographic algorithms

## Cryptographic Components

| Component | Version source | Function | License |
|---|---|---|---|
| OpenSSL (libssl3) | Ubuntu 22.04 apt | TLS/SSL, x509, symmetric ciphers | Apache 2.0 |
| OpenSSH server/client | Ubuntu 22.04 apt | SSH transport (chacha20, aes-gcm) | BSD |
| Python `cryptography` | PyPI | TLS bindings, x509, Fernet | Apache 2.0 / BSD |
| Python `paramiko` | PyPI (via deps) | SSH client library | LGPL |
| AWS CLI v2 | awscli.amazonaws.com | HTTPS to AWS APIs (TLS 1.2+) | Apache 2.0 |
| curl + ca-certificates | Ubuntu 22.04 apt | HTTPS transport | MIT / MPL |
| Nix daemon | nixos-25.05 | TLS to cache.nixos.org | MIT |
| GnuTLS / NSS | Ubuntu 22.04 apt | TLS backend for apt, glib | LGPL |

## Annual BIS Filing Requirement

Under 15 CFR 742.15(b), exporters relying on License Exception ENC for
5D002 items distributed to the public must submit an **Annual Self-Classification
Report** to the Bureau of Industry and Security (BIS).

**Deadline**: February 1 each year, covering sales from the prior calendar year.

**How to file**:
1. Register at SNAP-R: https://snapr.bis.doc.gov
2. Select **"Submit Annual Self-Classification Report for Encryption Items"**
3. Report type: **ANNUAL SELF-CLASSIFICATION REPORT**
4. ECCN: **5D002**
5. List each product/version sold, destination countries, approximate unit count

**What to report**: number of AMI subscriptions activated per country in the
prior year. AWS Marketplace provides this data in your seller reports.

**Consequence of non-filing**: civil penalties up to $300K per violation under
the Export Control Reform Act (ECRA). This filing is low-effort (< 1 hour/year)
and non-discretionary once you have paying customers.

## Restricted Destinations

This software must not be exported or re-exported to:
- Cuba, Iran, North Korea, Russia, Syria (comprehensive embargoes)
- Crimea, Donetsk, Luhansk regions (OFAC sanctions)
- Entities on the BIS Entity List or OFAC SDN List

AWS Marketplace automatically blocks purchases from embargoed regions.
As a seller, verify this setting is active in your Marketplace account:
Seller Portal → Settings → Export Compliance.

## AWS Marketplace Export Compliance Setting

In AWS Marketplace Seller Central:
- Navigate to: **Products → Your product → Additional details**
- Set **"Export classification"** to: `5D002`
- Set **"License exception"**: `ENC`
- This populates the product's export classification in the AWS catalog
  and activates automated geographic blocking.

## Record History

| Date | Action | By |
|---|---|---|
| 2026-05-17 | Initial self-classification, ECCN 5D002.c.1, ENC exception | bgajjela |

---

*This document is a seller-side compliance record. Keep it updated annually.*
*It is not legal advice. Consult export counsel if your product changes significantly.*
