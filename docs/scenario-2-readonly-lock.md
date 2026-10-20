# Scenario 2: ReadOnly Lock Applied Instead of CanNotDelete

**Ticket:** Lab Tester could create network resources in `rg-access-lab-app` the day before. Now every create fails, even though nobody changed their permissions.

**Status:** Resolved and verified · **Environment:** Personal Azure lab subscription (not production)

## 1. Symptom

Creating an NSG in `rg-access-lab-app` failed with **`ScopeLocked`**, not `AuthorizationFailed`.

> The scope `.../networkSecurityGroups/nsg-ticket-2` cannot perform **write** operation because following scope(s) are locked: `.../resourceGroups/rg-access-lab-app`.

Evidence: [`scenario-2-01-symptom.txt`](evidence/scenario-2-01-symptom.txt)

## 2. Initial Hypothesis

The error code separates this from a permissions issue. `AuthorizationFailed` means RBAC denied the request. `ScopeLocked` means RBAC **allowed** it and a resource lock blocked it. The error names the locked scope (the resource group), so the lock is inherited from the parent rather than set on the NSG itself.

## 3. Diagnostics

| Check | Command | Purpose |
|---|---|---|
| What the user can see | `az lock list --resource-group rg-access-lab-app` | Confirms the lock is visible to the user |
| Can the user remove it? | `az lock delete ...` (as user) | Determines whether this needs escalation |
| All locks at every level | `az lock list` (no resource group) | Finds locks on the subscription, resource groups, or resources |

## 4. Evidence

| Finding | Detail |
|---|---|
| Lock found | `lock-protect-app`, **ReadOnly**, on `rg-access-lab-app` |
| Lock note | *"Protect app resources from deletion"* |
| User can view the lock | ✅ Network Contributor includes read access to authorization settings |
| User can remove the lock | ❌ `AuthorizationFailed` on `Microsoft.Authorization/locks/delete`, so admin escalation is required |
| Other locks | None at the subscription or resource level |

Evidence: [`scenario-2-02-user-view.txt`](evidence/scenario-2-02-user-view.txt), [`scenario-2-03-diagnosis.txt`](evidence/scenario-2-03-diagnosis.txt)

## 5. Root Cause

**The lock type didn't match its stated purpose.** The note shows the admin intended to prevent deletion, but a **ReadOnly** lock blocks all writes (create, update, and delete). The intended protection was a **CanNotDelete** lock.

| Lock type | Read | Create/Modify | Delete |
|---|---|---|---|
| ReadOnly (applied) | ✅ | ❌ | ❌ |
| CanNotDelete (intended) | ✅ | ✅ | ❌ |

## 6. Remediation

1. Created **`lock-nodelete-app`** (CanNotDelete) on `rg-access-lab-app`
2. Then removed the ReadOnly lock

The new lock was added **before** the old one was removed, so the resource group was never without deletion protection.

Evidence: [`scenario-2-04-remediation.txt`](evidence/scenario-2-04-remediation.txt)

## 7. Verification

| Test (as Lab Tester) | Expected | Result |
|---|---|---|
| Create an NSG | Allowed | ✅ `Succeeded` |
| Delete `vnet-access-lab` | Blocked | ✅ `ScopeLocked` (delete operation) |

Evidence: [`scenario-2-05-verification.txt`](evidence/scenario-2-05-verification.txt)

## 8. Prevention

- Define locks in Bicep alongside the resources, so the lock type is reviewed in code
- Make the lock **name and note** describe the lock type, so a mismatch is obvious
- Before applying a ReadOnly lock, test it, because it can break routine operations (for example, listing storage account keys)

## Trade-offs and Notes

- CanNotDelete also blocks users from deleting **their own** resources. `nsg-ticket-2` stays in place until teardown, when an admin removes the lock first.
- Locks override RBAC: an **Owner** would have received the same `ScopeLocked` error.
- Only roles with `Microsoft.Authorization/locks/*` (such as Owner and User Access Administrator) can create or remove locks.
