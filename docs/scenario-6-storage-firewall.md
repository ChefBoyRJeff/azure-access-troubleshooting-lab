# Scenario 6: "Not Authorized" From Home — Storage Firewall

**Ticket:** After security restricted the storage account to the office network, Lab Tester could no longer read `report-q3.txt` from home, even though their permissions hadn't changed.

**Status:** Resolved and verified · **Environment:** Personal Azure lab subscription (not production)

## Background

Azure Storage evaluates requests in layers. A request must pass each one:

| Order | Layer | Question |
|---|---|---|
| 1 | Network (storage firewall) | Is the request coming from an allowed network? |
| 2 | Authentication | Who is the caller? |
| 3 | Authorization (RBAC data role, or a key or SAS) | What is the caller allowed to do? |

Account keys skip layer 3 (Scenario 5), but nothing skips layer 1.

## 1. Symptom

| Test | Result |
|---|---|
| Lab Tester, CLI with Entra ID | "The request may be blocked by network rules of storage account" |
| Lab Tester, raw Blob REST call | **`AuthorizationFailure`** (HTTP 403) |
| Admin (Owner) with the account key | Also blocked by network rules |

Evidence: [`scenario-6-02-symptom.txt`](evidence/scenario-6-02-symptom.txt), [`scenario-6-03-admin-key.txt`](evidence/scenario-6-03-admin-key.txt)

## 2. Initial Hypothesis

`AuthorizationFailure` is not the same as Scenario 5's `AuthorizationPermissionMismatch`. Because the account key was also blocked, the cause was before credentials were evaluated: the network layer.

## 3. Diagnostics and Evidence

| Check | Result |
|---|---|
| Baseline before the change | `defaultAction: Allow`, no rules |
| Network rules after the change | `defaultAction: Deny`, allowed IP `203.0.113.10` (the "office") only |
| Lab Tester's RBAC | Unchanged since Scenario 5 |
| Caller IP in the allowed list | **False** (compared in PowerShell without printing the address) |

Evidence: [`scenario-6-00-baseline.txt`](evidence/scenario-6-00-baseline.txt), [`scenario-6-01-misconfig.txt`](evidence/scenario-6-01-misconfig.txt), [`scenario-6-04-diagnosis.txt`](evidence/scenario-6-04-diagnosis.txt)

`203.0.113.10` is from a range reserved for documentation (RFC 5737); it is not a real office address.

## 4. Root Cause

**The storage firewall was enabled with a default action of Deny and only the office IP allowed, so requests from the user's home network were rejected at the network layer before RBAC was evaluated.**

| Error code | Layer | Fix |
|---|---|---|
| `AuthorizationFailure` | Network | Fix the network rules; RBAC changes won't help |
| `AuthorizationPermissionMismatch` | Data-plane RBAC | Grant a Storage ... Data role |

## 5. Remediation

Added a single IP rule for the caller's public address. Azure Storage IP rules take a plain address (they don't accept `/31` or `/32`) and only match public IPs.

| Option | Decision |
|---|---|
| Set `defaultAction` back to Allow | Rejected: removes the security control for every network |
| Allow a wide address range | Rejected: opens access to many unrelated users |
| **Add the caller's exact IP** | ✅ Chosen for this lab: the smallest opening; the office rule stays |
| VPN plus a private endpoint, with public access disabled | Recommended for a real organization (see Prevention) |

Evidence: [`scenario-6-05-remediation.txt`](evidence/scenario-6-05-remediation.txt) (the caller IP is not printed)

## 6. Verification

| Test (as Lab Tester) | Expected | Result |
|---|---|---|
| Read the blob from the allowed network | Allowed | ✅ File content returned |
| Upload a blob | Denied by RBAC, not by the network | ✅ Permissions error |

The upload test shows the layers are independent: opening the network did not grant any additional RBAC access.

Evidence: [`scenario-6-06-verification.txt`](evidence/scenario-6-06-verification.txt)

## 7. IaC Drift Check

**Hypothesis:** the Bicep template doesn't declare network rules, so a redeploy might reset the firewall to Allow.

| Check | Result |
|---|---|
| What-if | Storage account `NoChange` (other entries were known service-default noise) |
| Actual redeploy, then real state | Still `Deny`, 2 rules, office and caller rules present |

**Hypothesis ruled out.** Bicep only manages properties the template declares; it replaced `tags` in Scenario 4 because the template declares them, and left `networkAcls` alone here because it doesn't. The remaining gap is that the firewall exists only in Azure, so rebuilding from the repo would produce a storage account with no firewall.

Evidence: [`scenario-6-07-whatif-drift.txt`](evidence/scenario-6-07-whatif-drift.txt), [`scenario-6-08-post-redeploy.txt`](evidence/scenario-6-08-post-redeploy.txt)

## 8. Prevention

- For remote users, use the company VPN and a **private endpoint**, then **disable public network access**; home IPs change, and per-user IP lists don't scale
- Define `networkAcls` in Bicep, with allowed IPs passed as a deploy-time parameter rather than committed to the repo
- Communicate firewall changes before enabling them, and test from each user location the change affects
- When an error contains "Authorization," check which one: `AuthorizationFailure` (network) and `AuthorizationPermissionMismatch` (RBAC) need different fixes

## Notes

- The caller's public IP was never printed in evidence; files were also sanitized to replace it with `<caller-public-ip>`, and a leak check confirmed no evidence file contains it
- The storage firewall does not apply to Azure Resource Manager, so the admin could always manage the account even while data access was blocked
