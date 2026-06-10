# terraform-google-firewall-realtime-compliance-guardrail

![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.2-7B42BC?logo=terraform)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)
![Google Cloud Functions](https://img.shields.io/badge/Cloud-Functions%20(2nd%20gen)-4285F4?logo=googlecloud)

Terraform module that deploys a real-time event-driven guardrail to automatically
remediate VPC firewall rules that expose blocked ports to the public internet —
triggered within seconds of the API call being made.

GCP equivalent of
[terraform-aws-sg-realtime-compliance-guardrail](https://github.com/victorfengdj/terraform-aws-sg-realtime-compliance-guardrail) and
[terraform-azurerm-nsg-realtime-compliance-guardrail](https://github.com/victorfengdj/terraform-azurerm-nsg-realtime-compliance-guardrail).

---

## Project Abstract

A single misconfigured VPC firewall rule can expose critical ports — FTP, SSH,
Telnet, or RDP — directly to the public internet, creating an immediate attack
surface. Traditional compliance tools (e.g. Security Command Center scans) run on
a schedule and may not detect the exposure for minutes or hours.

`terraform-google-firewall-realtime-compliance-guardrail` eliminates that window.
Every `compute.firewalls.insert` and `compute.firewalls.patch` operation is
captured by Cloud Audit Logs, streamed through a Cloud Logging sink to Pub/Sub
within seconds, and evaluated by a Cloud Function. If the rule is an active
ingress rule that allows a blocked port from `0.0.0.0/0` or `::/0`, the offending
port is stripped from the rule immediately — or the rule is deleted entirely if
no compliant traffic remains.

The blocked port list is fully configurable via the `blocked_ports` Terraform
variable. No code changes are required to add or remove ports.

---

## Architecture Blueprint

```
Engineer or automation calls:
  compute.firewalls.insert / .patch (Compute Engine API)
        │
        ▼
┌─────────────────────────────┐
│  Cloud Audit Logs            │  Admin Activity log (always-on, no setup needed)
└──────────┬────────────────────┘
           │  log sink filter:
           │  resource.type="gce_firewall_rule"
           │  methodName IN (firewalls.insert, firewalls.patch)
           ▼
┌─────────────────────────────────────────────────────┐
│  Cloud Pub/Sub Topic                                 │
│  firewall-rule-change-events                         │
└──────────┬──────────────────────────────────────────┘
           │  Eventarc trigger (real-time, no delay)
           ▼
┌──────────────────────────────────────────────────────────────────┐
│  Cloud Function (2nd gen, Python 3.12)                            │
│  ────────────────────────────────────────────────────────────    │
│  1. Decode Pub/Sub message → Cloud Audit Log entry                │
│  2. Parse resourceName → project ID, firewall rule name           │
│  3. GET firewall rule via Compute Engine API                      │
│  4. Check: direction=INGRESS AND enabled                          │
│            AND source_ranges ∩ {0.0.0.0/0, ::/0}                  │
│            AND allowed[].ports ∩ BLOCKED_PORTS                    │
│  5. Violation → strip blocked ports from `allowed`;               │
│                  PATCH (compliant ports remain) or                │
│                  DELETE (if nothing compliant remains)            │
│  6. Compliant → log and exit, no action taken                     │
└──────────────────────────────────────────────────────────────────┘
           │
           ▼
  Rule remediated within seconds of the API call
  Full audit trail in Cloud Logging
```

| Component | Technology | Role |
|---|---|---|
| Event source | Cloud Audit Logs + Logging Sink | Captures every firewall rule insert/patch in real time |
| Event delivery | Cloud Pub/Sub + Eventarc | Real-time, durable delivery to the Cloud Function |
| Compliance logic | Cloud Functions 2nd gen (Python 3.12) | Evaluates rules; strips or deletes violating entries immediately |
| Blocked port config | Function env var (`BLOCKED_PORTS`) | Configurable list set by Terraform — no code changes needed |
| Authentication | Dedicated service account | Zero-credential SDK auth — no secrets stored anywhere |
| IAM | Custom role (`firewallComplianceRemediator`) | Least-privilege: `get`/`list`/`update`/`delete` on firewall rules only |
| Source storage | Cloud Storage bucket | Holds the zipped Cloud Function source for deployment |
| Infrastructure-as-Code | Terraform ≥ 1.2 | All resources declared, version-controlled, and reproducible |
| Remote state | HCP Terraform Cloud | State locking and team collaboration |

### Multi-cloud component mapping

| AWS (terraform-aws-sg-realtime-compliance-guardrail) | Azure (terraform-azurerm-nsg-realtime-compliance-guardrail) | GCP (this module) |
|---|---|---|
| AWS CloudTrail | Azure Activity Log | Cloud Audit Logs |
| Amazon EventBridge | Azure Event Grid (System Topic) | Cloud Pub/Sub + Eventarc |
| AWS Lambda (Python 3.14) | Azure Functions (Python 3.11) | Cloud Functions 2nd gen (Python 3.12) |
| IAM Role + inline policy | User-Assigned Managed Identity + Custom Role | Service Account + Custom IAM Role |
| EC2 Security Group | Network Security Group (NSG) | VPC Firewall Rule |
| `ec2:RevokeSecurityGroupIngress` | `security_rules.begin_delete()` | `firewalls.patch` / `firewalls.delete` |

### Default blocked ports

| Port | Service | Why it is blocked |
|---|---|---|
| 21 | FTP | Plaintext protocol — credentials transmitted in clear text |
| 22 | SSH | High-value brute-force target — use IAP TCP forwarding or Cloud VPN |
| 23 | Telnet | Plaintext — no legitimate use case in modern infrastructure |
| 3389 | RDP | Primary entry point for ransomware attacks against Windows hosts |

Override the defaults with the `blocked_ports` Terraform variable.

### GCP-specific source range handling

GCP VPC firewall rules represent unrestricted internet access with explicit CIDR
ranges — the function checks both:

| Notation | Meaning |
|---|---|
| `0.0.0.0/0` | All IPv4 addresses |
| `::/0` | All IPv6 addresses |

### Remediation strategy: patch vs. delete

Unlike a single security-group "revoke" or NSG-rule "delete", a GCP firewall
rule's `allowed[]` list can contain multiple protocol/port entries. The function
takes the least-disruptive compliant action:

- If only **some** ports in an `allowed` entry are blocked, the entry is
  **patched** to keep the compliant ports and drop the blocked ones.
- If **every** `allowed` entry becomes empty after removing blocked ports, the
  entire firewall rule is **deleted**.

---

## Usage

### As a Terraform module

```hcl
module "fw_compliance_guardrail" {
  source = "github.com/victorfengdj/terraform-google-firewall-realtime-compliance-guardrail"

  project_id         = "your-gcp-project-id"
  source_bucket_name = "fw-guardrail-source-bucket" # must be globally unique

  blocked_ports = [21, 22, 23, 3389]
}
```

### As a standalone deployment

```bash
git clone https://github.com/victorfengdj/terraform-google-firewall-realtime-compliance-guardrail.git
cd terraform-google-firewall-realtime-compliance-guardrail
terraform login        # authenticate with HCP Terraform (one-time)
terraform init
terraform plan
terraform apply
```

---

## Deployment Instructions

### Prerequisites

| Requirement | Version / Detail |
|---|---|
| [Terraform CLI](https://developer.hashicorp.com/terraform/downloads) | ≥ 1.2 |
| google provider | ~> 6.0 |
| archive provider | ~> 2.0 |
| [HCP Terraform account](https://app.terraform.io) | org `wgf`, workspace `terraform-google-firewall-realtime-compliance-guardrail` |
| GCP credentials | configured in the HCP Terraform workspace as environment variables (`GOOGLE_CREDENTIALS`) |
| Billing | The target GCP project must have billing enabled (required for Cloud Functions, Cloud Build, Eventarc) |

### Steps

```bash
# 1. Clone the repository
git clone https://github.com/victorfengdj/terraform-google-firewall-realtime-compliance-guardrail.git
cd terraform-google-firewall-realtime-compliance-guardrail

# 2. Authenticate with HCP Terraform (one-time setup)
terraform login

# 3. Initialise — downloads providers and connects to the remote workspace
terraform init

# 4. Preview the changes
terraform plan

# 5. Apply
terraform apply
```

> **Note:** Terraform enables all required APIs (`compute`, `cloudfunctions`,
> `cloudbuild`, `eventarc`, `pubsub`, `logging`, `run`, `artifactregistry`)
> automatically via `google_project_service`. The first `apply` may take a few
> extra minutes while these APIs activate.

### Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `project_id` | ✅ | — | GCP project ID where the guardrail is deployed |
| `source_bucket_name` | ✅ | — | Globally unique GCS bucket name for the Cloud Function source archive |
| `region` | | `us-central1` | GCP region for the Cloud Function, Pub/Sub topic, and source bucket |
| `blocked_ports` | | `[21, 22, 23, 3389]` | Ports that must not be exposed to the internet |
| `function_timeout` | | `60` | Cloud Function timeout in seconds |
| `function_memory` | | `256M` | Cloud Function memory allocation |

### Outputs

| Output | Description |
|---|---|
| `function_name` | Name of the deployed Cloud Function |
| `function_uri` | URI of the deployed Cloud Function |
| `service_account_email` | Email of the guardrail's dedicated service account |
| `pubsub_topic` | Pub/Sub topic that receives firewall rule change events |
| `log_sink_writer_identity` | Service account used by the Cloud Logging sink to publish events |

---

## Related Projects

- **[terraform-aws-sg-realtime-compliance-guardrail](https://github.com/victorfengdj/terraform-aws-sg-realtime-compliance-guardrail)** — AWS equivalent using EventBridge + Lambda + EC2 Security Groups.
- **[terraform-azurerm-nsg-realtime-compliance-guardrail](https://github.com/victorfengdj/terraform-azurerm-nsg-realtime-compliance-guardrail)** — Azure equivalent using Event Grid + Azure Functions + NSGs.
- **[terraform-aws-wafacl-golden](https://github.com/victorfengdj/terraform-aws-wafacl-golden)** — Enterprise CloudFront WAF ACL baseline.
- **[terraform-aws-fm-global-waf-policy](https://github.com/victorfengdj/terraform-aws-fm-global-waf-policy)** — Org-wide WAF enforcement via AWS Firewall Manager.
- **[terraform-aws-auto-remediate-waf-loss](https://github.com/victorfengdj/terraform-aws-auto-remediate-waf-loss)** — Serverless auto-remediation for CloudFront distributions that lose WAF protection.
