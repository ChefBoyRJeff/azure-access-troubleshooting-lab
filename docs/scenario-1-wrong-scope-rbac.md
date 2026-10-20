# Scenario 1: Role Assigned at the Wrong Scope

**Ticket:** Lab Tester was added to `grp-lab-app-contributors` to build network resources in `rg-access-lab-app`, but every create attempt failed.

**Status:** Resolved and verified · **Environment:** Personal Azure lab subscription (not production)

## 1. Symptom

Lab Tester received `AuthorizationFailed` when creating an NSG in `rg-access-lab-app`.

| Field | Value from the error |
|---|---|
| Who | `labtester@contoso.onmicrosoft.com` |
| Action | `Microsoft.Resources/subscriptions/resourcegroups/read` |
| Scope | `/subscriptions/<guid>/resourcegroups/rg-access-lab-app` |

The denied action was a **resource group read**, not the NSG write. The CLI reads the resource group first to look up its region, so the request failed before it attempted the create.

Evidence: [`scenario-1-01-symptom.txt`](evidence/scenario-1-01-symptom.txt)

## 2. Initial Hypothesis

The user's group either had no role on `rg-access-lab-app`, or had a role at a scope that doesn't apply to it.

## 3. Diagnostics

```powershell
az role assignment list --assignee <upn> --all --include-groups -o table
```

`--include-groups` is essential. The user had **no direct** assignments, so without it the output would wrongly suggest the user had no access anywhere.

## 4. Evidence

| Principal | Role | Scope |
|---|---|---|
| grp-lab-app-contributors | Contributor | `.../resourceGroups/rg-access-lab-other` |

Evidence: [`scenario-1-02-diagnosis.txt`](evidence/scenario-1-02-diagnosis.txt)

## 5. Root Cause

**Contributor was assigned to the group on `rg-access-lab-other` instead of `rg-access-lab-app`.** RBAC permissions inherit only downward from the assigned scope, so a role on one resource group grants nothing on a sibling resource group. The group's name implied the correct target, but Azure evaluates only the assignment's actual scope.

## 6. Remediation

1. Assigned **Network Contributor** (not Contributor) to the group on `rg-access-lab-app`. This is the least-privilege built-in role covering the ticket's requirement.
2. Removed the wrong-scope Contributor assignment from `rg-access-lab-other` to eliminate unneeded access.

Evidence: [`scenario-1-03-remediation.txt`](evidence/scenario-1-03-remediation.txt)

## 7. Verification

| Test | Expected | Result |
|---|---|---|
| Create and read an NSG in `rg-access-lab-app` | Success | ✅ `Succeeded` |
| Create a storage account in `rg-access-lab-app` (negative test) | Denied | ✅ `AuthorizationFailed` on `Microsoft.Storage/storageAccounts/write` |

The first retry after remediation still failed. The fix worked after the role assignment had time to apply and Lab Tester signed in again. In a real ticket, the user would be asked to sign out and back in before the ticket is closed.

Evidence: [`scenario-1-04-verification.txt`](evidence/scenario-1-04-verification.txt), [`scenario-1-05-negative-test.txt`](evidence/scenario-1-05-negative-test.txt)

## 8. Prevention

- Define role assignments in Bicep so the intended scope is reviewed in code rather than typed by hand
- Name groups after their scope, and confirm the assignment scope matches the name during review
- Run periodic access reviews to catch assignments on resources a group doesn't need

## Lesson Learned During Testing: Verify the Test Identity

The first reproduction attempt **succeeded** when it should have failed. The Activity Log showed the caller was the **admin** account, not Lab Tester: the separate CLI profile had cached the admin sign-in. Re-authenticating that profile with a device code in a private browser window fixed it.

**Rule:** before trusting an access test, confirm the identity with `az account show --query user.name`.

Evidence: [`scenario-1-00-activity-log.txt`](evidence/scenario-1-00-activity-log.txt) (shows the admin account as the caller). The original success output was overwritten by the corrected re-test, so the Activity Log is the record of the wrong-identity run.
