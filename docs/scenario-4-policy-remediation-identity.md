# Scenario 4: Policy Remediation Failed — Managed Identity Had No Role

**Ticket:** Two resources in `rg-access-lab-app` were still missing the `costCenter` tag. A policy was set up to tag resources automatically, but its remediation task showed as **Failed**.

**Status:** Resolved and verified · **Environment:** Personal Azure lab subscription (not production)

## Background

Scenario 3 left two pre-existing resources (`vnet-access-lab`, `nsg-ticket-2`) non-compliant with the required `costCenter` tag. To fix them without manual edits, the built-in policy **Inherit a tag from the resource group if missing** (Modify effect) was assigned with a **system-assigned managed identity**, and a remediation task was created.

| Concept | Role in this scenario |
|---|---|
| Modify effect | Adds the missing tag instead of blocking the request |
| Remediation task | Applies a Modify policy to resources that already exist |
| Managed identity | The identity the remediation runs as; it starts with **no permissions** |

## 1. Symptom

The remediation task ended in `Failed`, with 2 of 2 deployments failing:

> The client `<guid>` ... does not have authorization to perform action **`Microsoft.Resources/tags/write`** ... The 'PATCH' request failed with status code: **Forbidden**.

Evidence: [`scenario-4-01-symptom.txt`](evidence/scenario-4-01-symptom.txt)

## 2. Initial Hypothesis

The policy assignment's managed identity had no RBAC role. When a Modify policy is assigned in the Azure portal, Azure grants the roles listed in the definition's `roleDefinitionIds` automatically. The assignment here was created with the **CLI**, which only grants a role when `--role` and `--identity-scope` are supplied.

## 3. Diagnostics

| Check | Command | Result |
|---|---|---|
| Identity's roles | `az role assignment list --assignee <identity-object-id> --all` | **None** |
| Role the definition declares | `az policy definition show ... --query policyRule.then.details.roleDefinitionIds` | Contributor |
| Identity in the error matches the assignment | Compared `identity.principalId` to the object ID in the error | Match |

The hypothesis was tested **while the task was still evaluating**, before the failure appeared, by checking the identity's role assignments directly.

Evidence: [`scenario-4-02-diagnosis.txt`](evidence/scenario-4-02-diagnosis.txt)

## 4. Root Cause

**The policy assignment's managed identity had no role on the resource group.** The assignment was scripted with the CLI without granting a role, so the remediation's `PATCH` requests to write tags were rejected as `Forbidden`.

## 5. Remediation: Least Privilege Based on Evidence

The definition declares **Contributor**, which can create, change, or delete almost any resource. But the error showed the only action required was **`Microsoft.Resources/tags/write`**.

| Option | Decision |
|---|---|
| Contributor (declared by the definition) | Not used: far broader than the observed requirement |
| **Tag Contributor on `rg-access-lab-app`** | ✅ Chosen: covers tag writes only, scoped to the resource group, and tested before closing |

Evidence: [`scenario-4-03-remediation.txt`](evidence/scenario-4-03-remediation.txt)

## 6. Verification

A new remediation task (`remediate-costcenter-retry`) was created after the role had time to take effect.

| Check | Result |
|---|---|
| Remediation state | ✅ `Succeeded`, 2 of 2 deployments |
| `vnet-access-lab` costCenter | ✅ `CC-1001` |
| `nsg-ticket-2` costCenter | ✅ `CC-1001` |

**Tag Contributor was sufficient**, which confirms the narrower role met the requirement.

Evidence: [`scenario-4-04-verification.txt`](evidence/scenario-4-04-verification.txt)

## 7. Prevention

- When scripting Modify or DeployIfNotExists assignments, always include `--role` and `--identity-scope`, or create the role assignment in the same script
- Check the failing action in the error before choosing a role, rather than defaulting to the role declared in the definition
- Define policy assignments and identity role assignments in Bicep so the identity's permissions are reviewed with the policy
- Add `costCenter` to the Bicep `tags` parameter. Otherwise, a redeployment would overwrite the resource group's tags and remove the tag the policy inherits from.

## Notes

- A failed remediation task can't be restarted; a new task must be created
- The first task used `ReEvaluateCompliance` (about 10 minutes); the retry used existing compliance data (about 1 minute)
- RBAC changes for managed identities may take several minutes to apply
## 8. Prevention Implemented: IaC Tag Drift

Bicep `tags` replace a resource's existing tags. The baseline template didn't include `costCenter`, so a redeployment would have removed it from `rg-access-lab-app` (the tag the Modify policy inherits from) and from `vnet-access-lab`.

| What-if | `rg-access-lab-app` | `vnet-access-lab` |
|---|---|---|
| Before fix | Removes `costCenter` | Removes `costCenter` |
| After adding `costCenter` to the `tags` parameter | NoChange | `costCenter` kept |

What-if also reported `privateEndpointVNetPolicies` as removed. This was checked after deployment and the value was unchanged (`Disabled`), confirming it was what-if noise caused by a service default not declared in the template.

Evidence: [`scenario-4-05-whatif-before.txt`](evidence/scenario-4-05-whatif-before.txt), [`scenario-4-06-whatif-after.txt`](evidence/scenario-4-06-whatif-after.txt), [`scenario-4-07-post-deploy.txt`](evidence/scenario-4-07-post-deploy.txt)
