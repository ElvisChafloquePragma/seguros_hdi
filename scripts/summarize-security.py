#!/usr/bin/env python3
"""Resume los reportes de seguridad (Gitleaks, Semgrep, npm audit, Checkov) en texto compacto.

Evita enviar JSON de cientos de KB a Bedrock: solo se incluyen conteos y los hallazgos.
Uso: summarize-security.py <directorio_reports> <archivo_salida>
"""
import json
import os
import sys


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as exc:
        return {"_error": str(exc)}


def main():
    reports_dir, out_file = sys.argv[1], sys.argv[2]
    lines = []

    gl = load(os.path.join(reports_dir, "gitleaks-all.json"))
    if isinstance(gl, list):
        lines.append("GITLEAKS (secretos): %d secretos detectados." % len(gl))
        for f in gl[:10]:
            lines.append("  - %s en %s" % (f.get("RuleID"), f.get("File")))
    elif gl.get("status") == "skipped_tool_missing":
        lines.append("GITLEAKS: NO EJECUTADO (herramienta no instalada).")
    else:
        lines.append("GITLEAKS: sin reporte valido (%s)." % gl.get("_error", "formato desconocido"))

    sg = load(os.path.join(reports_dir, "semgrep-sast.json"))
    if sg.get("status") == "skipped_tool_missing":
        lines.append("SEMGREP (SAST): NO EJECUTADO (herramienta no instalada).")
    elif "results" in sg:
        lines.append("SEMGREP (SAST): %d hallazgos." % len(sg["results"]))
        for r in sg["results"][:10]:
            lines.append("  - %s en %s" % (r.get("check_id"), r.get("path")))
    else:
        lines.append("SEMGREP: sin reporte valido.")

    na = load(os.path.join(reports_dir, "npm-audit-backend.json"))
    vulns = na.get("metadata", {}).get("vulnerabilities")
    if vulns:
        lines.append(
            "NPM AUDIT (SCA): critical=%s high=%s moderate=%s low=%s total=%s."
            % (vulns.get("critical"), vulns.get("high"), vulns.get("moderate"), vulns.get("low"), vulns.get("total"))
        )
    else:
        lines.append("NPM AUDIT: sin reporte valido.")

    ck = load(os.path.join(reports_dir, "checkov-iac.json"))
    if ck.get("status") == "skipped_tool_missing":
        lines.append("CHECKOV (IaC): NO EJECUTADO (herramienta no instalada).")
    elif "summary" in ck:
        s = ck["summary"]
        failed = ck.get("results", {}).get("failed_checks", [])
        lines.append("CHECKOV (IaC): %s pasaron, %s fallaron." % (s.get("passed"), s.get("failed")))
        seen = set()
        for c in failed:
            key = (c.get("check_id"), c.get("check_name"))
            if key not in seen:
                seen.add(key)
                lines.append("  - %s: %s" % key)
    else:
        lines.append("CHECKOV: sin reporte valido.")

    with open(out_file, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
