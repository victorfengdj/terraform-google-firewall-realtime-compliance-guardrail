"""
Real-Time Firewall Compliance Guardrail — GCP Cloud Function
==============================================================
Triggered by Cloud Pub/Sub whenever a VPC firewall rule is created or
updated (compute.firewalls.insert / compute.firewalls.patch), captured
by a Cloud Logging sink reading Cloud Audit Logs (Admin Activity, always-on).

Logic:
  1. Decode the Pub/Sub message into the underlying Cloud Audit Log entry.
  2. Extract the project ID and firewall rule name from the log entry's
     resourceName (projects/<project>/global/firewalls/<rule-name>).
  3. Fetch the full firewall rule via the Compute Engine API.
  4. Check whether the rule is an active INGRESS rule whose source ranges
     include 0.0.0.0/0 or ::/0 and whose `allowed` entries include a
     blocked TCP/UDP port.
  5. Violation found:
       - Strip the blocked ports from the offending `allowed` entry.
       - If no `allowed` entries remain, delete the firewall rule entirely.
       - Otherwise, patch the rule with only the remaining (compliant)
         allowed entries.
  6. Log every decision (VIOLATION / COMPLIANT / REMEDIATED / DELETED) to
     Cloud Logging for audit purposes.

Blocked ports are read from the BLOCKED_PORTS environment variable (comma-
separated integers), set by Terraform. Default covers the highest-risk ports:
  21   — FTP    (plaintext, credential exposure)
  22   — SSH    (brute-force target — use IAP TCP forwarding or Cloud VPN instead)
  23   — Telnet (plaintext — no legitimate use in modern infrastructure)
  3389 — RDP    (primary ransomware entry point for Windows hosts)

Authentication uses the dedicated service account attached to the Cloud
Function — no credentials or secrets are stored in code or config.
"""

import os
import json
import base64
import logging

import functions_framework
from cloudevents.http import CloudEvent
from google.cloud import compute_v1

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── Configuration — read once per cold start ──────────────────────────────────

BLOCKED_PORTS: set[int] = set(
    int(p.strip())
    for p in os.environ.get("BLOCKED_PORTS", "21,22,23,3389").split(",")
    if p.strip().isdigit()
)

# Source ranges that represent unrestricted internet access.
PUBLIC_RANGES = {"0.0.0.0/0", "::/0"}

DEFAULT_PROJECT = os.environ.get("GCP_PROJECT", "")


# ── Port range helpers ────────────────────────────────────────────────────────

def ports_from_entry(ports: list[str]) -> set[int]:
    """
    Expand an `allowed[].ports` list (e.g. ["20-23", "3389"]) into a set of
    individual port integers.
    """
    expanded: set[int] = set()
    for p in ports:
        if "-" in p:
            lo, hi = p.split("-", 1)
            expanded.update(range(int(lo), int(hi) + 1))
        else:
            expanded.add(int(p))
    return expanded


def collapse_ports(ports: set[int]) -> list[str]:
    """Collapse a set of ports back into a sorted list of individual port strings."""
    return [str(p) for p in sorted(ports)]


# ── Main function handler ─────────────────────────────────────────────────────

@functions_framework.cloud_event
def fw_guardrail(cloud_event: CloudEvent) -> None:
    """
    Cloud Function entry point — invoked by Eventarc/Pub/Sub on every Cloud
    Audit Log entry matching a firewall insert/patch operation.
    """
    envelope = cloud_event.data.get("message", {})
    raw_data = envelope.get("data", "")
    if not raw_data:
        logger.info("Empty Pub/Sub message — skipping")
        return

    log_entry = json.loads(base64.b64decode(raw_data).decode("utf-8"))
    proto_payload = log_entry.get("protoPayload", {})

    method_name = proto_payload.get("methodName", "")
    resource_name = proto_payload.get("resourceName", "")
    actor = proto_payload.get("authenticationInfo", {}).get("principalEmail", "unknown")

    logger.info(f"Operation: {method_name} | Resource: {resource_name} | Actor: {actor}")

    if "compute.firewalls" not in method_name:
        logger.info("Not a firewall rule operation — skipping")
        return

    # resourceName format: projects/<project>/global/firewalls/<rule-name>
    parts = resource_name.split("/")
    if len(parts) < 4 or parts[-2] != "firewalls":
        logger.warning(f"Could not parse resource name: {resource_name!r} — skipping")
        return

    project_id = parts[1] or DEFAULT_PROJECT
    rule_name = parts[-1]

    logger.info(f"Evaluating firewall rule: project={project_id} rule={rule_name}")

    client = compute_v1.FirewallsClient()

    try:
        rule = client.get(project=project_id, firewall=rule_name)
    except Exception as e:
        logger.error(f"Failed to fetch firewall rule {rule_name}: {e}")
        return

    if rule.direction != "INGRESS" or rule.disabled:
        logger.info(f"COMPLIANT: rule={rule_name} — not an active ingress rule, no action taken")
        return

    source_ranges = set(rule.source_ranges)
    if not source_ranges.intersection(PUBLIC_RANGES):
        logger.info(f"COMPLIANT: rule={rule_name} — no public source ranges, no action taken")
        return

    # Evaluate each `allowed` entry for blocked ports.
    remaining_allowed: list[dict] = []
    violation_found = False

    for entry in rule.allowed:
        protocol = entry.i_p_protocol.lower()
        entry_ports = list(entry.ports)

        if protocol not in ("tcp", "udp") or not entry_ports:
            # Protocols without ports (e.g. icmp, "all") are left untouched.
            remaining_allowed.append({"i_p_protocol": entry.i_p_protocol, "ports": entry_ports})
            continue

        expanded_ports = ports_from_entry(entry_ports)
        blocked_overlap = expanded_ports.intersection(BLOCKED_PORTS)

        if not blocked_overlap:
            remaining_allowed.append({"i_p_protocol": entry.i_p_protocol, "ports": entry_ports})
            continue

        violation_found = True
        safe_ports = expanded_ports - blocked_overlap

        logger.warning(
            f"VIOLATION: rule={rule_name} protocol={protocol} "
            f"blocked_ports={sorted(blocked_overlap)} "
            f"source_ranges={sorted(source_ranges)} actor={actor}"
        )

        if safe_ports:
            remaining_allowed.append({
                "i_p_protocol": entry.i_p_protocol,
                "ports": collapse_ports(safe_ports),
            })

    if not violation_found:
        logger.info(f"COMPLIANT: rule={rule_name} — no blocked ports exposed, no action taken")
        return

    if not remaining_allowed:
        # Every allowed entry was fully non-compliant — delete the rule entirely.
        logger.warning(f"DELETING rule={rule_name} — all allowed traffic is non-compliant")
        try:
            client.delete(project=project_id, firewall=rule_name)
            logger.info(f"DELETED: rule={rule_name}")
        except Exception as e:
            logger.error(f"Failed to delete rule {rule_name}: {e}")
        return

    # Patch the rule, keeping only the remaining compliant allowed entries.
    firewall_resource = compute_v1.Firewall(
        allowed=[
            compute_v1.Allowed(i_p_protocol=e["i_p_protocol"], ports=e["ports"])
            for e in remaining_allowed
        ]
    )

    try:
        client.patch(project=project_id, firewall=rule_name, firewall_resource=firewall_resource)
        logger.info(f"REMEDIATED: rule={rule_name} — blocked ports removed, compliant ports retained")
    except Exception as e:
        logger.error(f"Failed to patch rule {rule_name}: {e}")
