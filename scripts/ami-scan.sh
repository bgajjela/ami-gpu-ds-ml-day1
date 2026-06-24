#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
# ami-scan — on-demand CVE and CIS compliance scanner.
#
# Usage:
#   sudo ami-scan            run both CVE and CIS scans
#   sudo ami-scan --cve      CVE scan only  (Trivy,    ~1-2 min)
#   sudo ami-scan --cis      CIS scan only  (OpenSCAP, ~3-5 min)
#   sudo ami-scan --json     machine-readable output only (no table)
#   sudo ami-scan --out DIR  write reports to DIR (default: /var/log/ami-scan)
#
# Results are written to OUTDIR and symlinked as latest-*.
# Nothing runs automatically — invoke this whenever compliance evidence is needed.
set -euo pipefail

# ── Argument parsing ─────────────────────────────────────────────────────────
RUN_CVE=true
RUN_CIS=true
JSON_ONLY=false
OUTDIR="/var/log/ami-scan"
PROFILE_LABEL="Level 2 Server"
PROFILE="xccdf_org.ssgproject.content_profile_cis_level2_server"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cve)  RUN_CIS=false ;;
    --cis)  RUN_CVE=false ;;
    --cis-level1)
      RUN_CVE=false
      RUN_CIS=true
      PROFILE_LABEL="Level 1 Server"
      PROFILE="xccdf_org.ssgproject.content_profile_cis_level1_server" ;;
    --cis-level2)
      RUN_CVE=false
      RUN_CIS=true
      PROFILE_LABEL="Level 2 Server"
      PROFILE="xccdf_org.ssgproject.content_profile_cis_level2_server" ;;
    --json) JSON_ONLY=true ;;
    --out)  OUTDIR="$2"; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# //'
      exit 0 ;;
    *) echo "Unknown option: $1  (try --help)" >&2; exit 1 ;;
  esac
  shift
done

# ── Setup ────────────────────────────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: ami-scan must run as root (sudo ami-scan)" >&2
  exit 1
fi

mkdir -p "${OUTDIR}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OVERALL_EXIT=0

_header() { [[ "${JSON_ONLY}" == false ]] && echo "" && echo "=== $* ==="; }
_info()   { [[ "${JSON_ONLY}" == false ]] && echo "  $*"; }

# ── CVE scan (Trivy) ─────────────────────────────────────────────────────────
if [[ "${RUN_CVE}" == true ]]; then
  _header "CVE scan — Trivy (HIGH and CRITICAL only)"

  if ! command -v trivy >/dev/null 2>&1; then
    echo "ERROR: trivy not found. It should be at /usr/local/bin/trivy." >&2
    echo "       Re-launch from a current version of this AMI." >&2
    OVERALL_EXIT=1
  else
    JSON_OUT="${OUTDIR}/trivy-${TS}.json"

    # Always write JSON (machine-readable)
    trivy rootfs / \
      --scanners vuln \
      --severity HIGH,CRITICAL \
      --format json \
      --output "${JSON_OUT}" \
      --quiet

    ln -sf "${JSON_OUT}" "${OUTDIR}/latest-cve.json"

    # Human-readable table unless --json
    if [[ "${JSON_ONLY}" == false ]]; then
      trivy rootfs / \
        --scanners vuln \
        --severity HIGH,CRITICAL \
        --format table \
        --quiet
    fi

    # Count findings and set exit code
    HIGH=$(python3 -c "
import json, sys
data = json.load(open('${JSON_OUT}'))
results = data.get('Results', [])
vulns = [v for r in results for v in r.get('Vulnerabilities', []) or []]
highs  = sum(1 for v in vulns if v.get('Severity') == 'HIGH')
crits  = sum(1 for v in vulns if v.get('Severity') == 'CRITICAL')
print(highs, crits)
" 2>/dev/null || echo "0 0")
    H=$(echo "${HIGH}" | awk '{print $1}')
    C=$(echo "${HIGH}" | awk '{print $2}')

    _info "HIGH: ${H}   CRITICAL: ${C}"
    _info "Report: ${JSON_OUT}"

    if [[ "${C}" -gt 0 ]]; then
      _info "RESULT: CRITICAL CVEs present — remediation required"
      OVERALL_EXIT=1
    elif [[ "${H}" -gt 0 ]]; then
      _info "RESULT: HIGH CVEs present — review recommended"
    else
      _info "RESULT: PASS — no HIGH or CRITICAL CVEs found"
    fi
  fi
fi

# ── CIS scan (OpenSCAP) ──────────────────────────────────────────────────────
if [[ "${RUN_CIS}" == true ]]; then
  _header "CIS Benchmark — OpenSCAP (Ubuntu 22.04 ${PROFILE_LABEL})"

  SCAP_DS="/usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml"

  if ! command -v oscap >/dev/null 2>&1; then
    echo "ERROR: oscap not found. Re-launch from a current version of this AMI." >&2
    OVERALL_EXIT=1
  elif [[ ! -f "${SCAP_DS}" ]]; then
    echo "ERROR: SCAP data stream not found at ${SCAP_DS}." >&2
    echo "       Re-launch from a current version of this AMI with bundled Ubuntu 22.04 SSG content." >&2
    OVERALL_EXIT=1
  else
    XML_OUT="${OUTDIR}/oscap-${TS}.xml"
    HTML_OUT="${OUTDIR}/oscap-${TS}.html"

    # oscap exits non-zero when rules fail — we want the report regardless
    oscap xccdf eval \
      --profile "${PROFILE}" \
      --results "${XML_OUT}" \
      --report  "${HTML_OUT}" \
      "${SCAP_DS}" || true

    ln -sf "${XML_OUT}"  "${OUTDIR}/latest-cis.xml"
    ln -sf "${HTML_OUT}" "${OUTDIR}/latest-cis.html"

    # Parse pass/fail counts from XML
    if command -v python3 >/dev/null 2>&1; then
      COUNTS=$(python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('${XML_OUT}')
ns = {'x': 'http://checklists.nist.gov/xccdf/1.2'}
results = tree.findall('.//x:rule-result', ns)
pass_  = sum(1 for r in results if r.find('x:result', ns) is not None and r.find('x:result', ns).text == 'pass')
fail_  = sum(1 for r in results if r.find('x:result', ns) is not None and r.find('x:result', ns).text == 'fail')
notapp = sum(1 for r in results if r.find('x:result', ns) is not None and r.find('x:result', ns).text in ('notapplicable','notselected'))
print(pass_, fail_, notapp)
" 2>/dev/null || echo "? ? ?")
      PASS=$(echo "${COUNTS}" | awk '{print $1}')
      FAIL=$(echo "${COUNTS}" | awk '{print $2}')
      _info "PASS: ${PASS}   FAIL: ${FAIL}"
    fi

    _info "XML results: ${XML_OUT}"
    _info "HTML report: ${HTML_OUT}  (copy to your browser to view)"
    _info "Symlink:     ${OUTDIR}/latest-cis.html"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
_header "Summary"
_info "Timestamp:   ${TS}"
_info "Reports in:  ${OUTDIR}/"
_info "Build-time provenance: /usr/share/BUILD_INFO/"

if [[ "${OVERALL_EXIT}" -ne 0 ]]; then
  _info "OVERALL: Issues found — see reports above"
else
  _info "OVERALL: PASS"
fi

exit "${OVERALL_EXIT}"
