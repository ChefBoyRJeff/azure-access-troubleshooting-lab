# Scenario 3: Deployment Blocked by a Required-Tag Policy

**Ticket:** Lab Tester still had the right role, and the lock issue was fixed, but creating an NSG now failed with an error mentioning a policy.

**Status:** Resolved and verified · **Environment:** Personal Azure lab subscription (not production)

## 1. Symptom

Creating an NSG in `rg-access-lab-app` failed with **`RequestDisallowedByPolicy`**. The error named the policy assignment (**Require costCenter tag**) and the built-in definition (**Require a tag on resources**).

Evidence: [`scenario-3-01-symptom.txt`](evidence/scenario-3-01-symptom.txt)

## 2. Initial Hypothesis

This is the third type of "access denied" in this lab, and the error code identifies which control blocked the request:

| Error code | Blocked by |
|---|---|
| `AuthorizationFailed` | RBAC: who the caller is (Scenario 1) |
| `ScopeLocked` | A resource lock (Scenario 2) |
| `RequestDisallowedByPolicy` | **Azure Policy: what is being deployed** |

Because the request was evaluated against a policy, the hypothesis was that the NSG didn't meet a policy requirement, not that the user lacked permission.

## 3. Diagnostics

The user can investigate this themselves: Network Contributor includes read access to policy assignments.

```powershell
az policy assignment list --resource-group rg-access-lab-app --query "[].{name:name, displayName:displayName, parameters:parameters}"
```

## 4. Evidence

| Field | Value |
|---|---|
| Assignment | `require-costcenter-tag` (*Require costCenter tag*) |
| Scope | `rg-access-lab-app` |
| Effect | Deny |
| Parameter | `tagName: costCenter` |

Evidence: [`scenario-3-02-diagnosis.txt`](evidence/scenario-3-02-diagnosis.txt)

## 5. Root Cause

**The policy worked as designed. The request was missing a required tag.** A Deny policy requiring a `costCenter` tag was assigned to the resource group, and the user's create command didn't include that tag.

The underlying cause was the **rollout process**: the policy was enforced with Deny immediately, with no audit period and no notice to users, so routine work started failing without warning.

## 6. Remediation

The user re-ran the request **with the required tag**. Governance wasn't changed: no exemption, no switch to Audit, no deleted assignment.

```powershell
az network nsg create --resource-group rg-access-lab-app --name nsg-ticket-3 --tags costCenter=CC-1001
```

| Option considered | Decision |
|---|---|
| Delete the policy or switch it to Audit | Rejected: removes the finance control for everyone |
| Policy exemption | Rejected: meant for justified exceptions, not a missing tag |
| **Add the required tag** | ✅ Chosen: compliant request, no change to governance |

## 7. Verification

| Test | Expected | Result |
|---|---|---|
| Create an NSG with `costCenter=CC-1001` | Allowed | ✅ `Succeeded`, tag present |

Evidence: [`scenario-3-03-verification.txt`](evidence/scenario-3-03-verification.txt)

## 8. Impact on Existing Resources

A compliance scan showed resources that existed **before** the policy are now **non-compliant**: `vnet-access-lab` and `nsg-ticket-2`. Deny didn't delete or modify them; it only affects new create and update requests. Any future **update** to these resources without adding the tag will also be denied, **including a Bicep redeployment of the baseline**, because the template's `tags` parameter doesn't include `costCenter` yet.

Evidence: [`scenario-3-04-noncompliant.txt`](evidence/scenario-3-04-noncompliant.txt)

## 9. Prevention

- Roll out new Deny policies in stages: assign with **enforcement mode disabled** (`DoNotEnforce`) or the **Audit** effect first, review the results, announce, then enforce
- Publish required tags before enforcement
- Use the **Modify** effect to add tags automatically where possible (see Scenario 4)
- Add `costCenter` to the Bicep `tags` parameter so IaC deployments stay compliant
