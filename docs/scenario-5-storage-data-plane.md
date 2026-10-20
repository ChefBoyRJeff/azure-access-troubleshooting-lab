# Scenario 5: "I Can't Read the Blob" — Control Plane vs. Data Plane

**Ticket:** Lab Tester was given access to read finance reports in the `reports` container, but every attempt to read `report-q3.txt` failed.

**Status:** Resolved and verified · **Environment:** Personal Azure lab subscription (not production)

## Background

Azure Storage has two separate permission systems:

| | Control plane | Data plane |
|---|---|---|
| Manages | The storage account (settings, keys, firewall) | The data (blobs, files) |
| Example roles | Owner, Contributor, Reader | Storage Blob Data Reader / Contributor / Owner |

Account keys and SAS tokens bypass RBAC entirely. Any role that can list keys (`Microsoft.Storage/storageAccounts/listKeys/action`), such as Owner or Contributor, can therefore reach the data indirectly. Reader cannot list keys.

## 1. Symptom

Reading the blob with Entra ID returned **`AuthorizationPermissionMismatch`** (raw Blob service response). The Azure CLI replaced it with a friendly message listing only **Storage ... Data** roles.

The same happened to the **admin account (Owner)** when uploading with `--auth-mode login`. The admin upload succeeded only with `--auth-mode key`, after the CLI retrieved the account key.

Evidence: [`scenario-5-02-owner-login-upload.txt`](evidence/scenario-5-02-owner-login-upload.txt), [`scenario-5-04-symptom.txt`](evidence/scenario-5-04-symptom.txt)

## 2. Initial Hypothesis

The user's group had a control-plane role on the storage account but no data-plane role, so the request was **authenticated but not authorized**.

## 3. Diagnostics

| Test (as Lab Tester) | Result | Meaning |
|---|---|---|
| Read the storage account (ARM) | ✅ Visible | Reader works for the control plane |
| Read blob via CLI, Entra ID | ❌ Friendly permissions error | Data-plane role missing |
| Read blob via REST, Entra ID token | ❌ `AuthorizationPermissionMismatch` | Raw code: valid identity, no data role |
| Read blob via account key | ❌ `AuthorizationFailed` on `listKeys/action`, then `NoAuthenticationInformation` | Reader can't list keys, so the CLI sent the request with no credentials |
| Anonymous request | ❌ `PublicAccessNotPermitted` | `allowBlobPublicAccess: false` works |
| Request with a fake SAS signature | ❌ `AuthenticationFailed` ("Signature did not match") | Invalid credential |

Role assignments at the time: **Network Contributor** (resource group) and **Reader** (storage account).

Evidence: [`scenario-5-03-misconfig.txt`](evidence/scenario-5-03-misconfig.txt), [`scenario-5-04-symptom.txt`](evidence/scenario-5-04-symptom.txt), [`scenario-5-05-anonymous-test.txt`](evidence/scenario-5-05-anonymous-test.txt), [`scenario-5-06-authn-test.txt`](evidence/scenario-5-06-authn-test.txt)

## 4. Authentication vs. Authorization

| Error code | Kind | Meaning |
|---|---|---|
| `NoAuthenticationInformation` | Authentication | No credentials sent |
| `AuthenticationFailed` | Authentication | Credentials sent but invalid |
| `AuthorizationPermissionMismatch` | Authorization (data plane) | Valid identity, missing a data role |
| `AuthorizationFailed` | Authorization (control plane) | Valid identity, missing a management permission |

The ticket's error was an **authorization** failure: Azure knew who the user was, so fixing credentials or signing in again would not help.

## 5. Root Cause

**The group was assigned Reader, a control-plane role, which grants no access to blob data.** Reading a blob with Entra ID requires a data-plane role.

## 6. Remediation

1. Assigned **Storage Blob Data Reader** to the group, scoped to the **`reports` container** only
2. Removed the account-level **Reader** assignment, which the ticket didn't require

| Option | Decision |
|---|---|
| Storage Blob Data Contributor | Rejected: allows writes and deletes |
| Storage Blob Data Reader on the account | Rejected: covers every current and future container |
| **Storage Blob Data Reader on the container** | ✅ Chosen: read-only, limited to where the data lives |
| Share an account key or SAS | Rejected: bypasses RBAC and isn't tied to a person |

### Unexpected Finding: The Lock Blocked Removing Access

Deleting the Reader assignment failed with **`ScopeLocked`**. The CanNotDelete lock from Scenario 2 applies to role assignments inside `rg-access-lab-app`, even for an Owner. With approval, the lock was removed, the assignment deleted, and the lock recreated immediately. The Activity Log shows the lock deleted at 22:15:20 UTC and recreated at 22:15:24 UTC: the resource group was unprotected for about **4 seconds**.

Evidence: [`scenario-5-07-remediation.txt`](evidence/scenario-5-07-remediation.txt), [`scenario-5-07a-lock-blocked-delete.txt`](evidence/scenario-5-07a-lock-blocked-delete.txt)

## 7. Verification

| Test (as Lab Tester, after fresh sign-in) | Expected | Result |
|---|---|---|
| Read `report-q3.txt` with Entra ID | Allowed | ✅ File content returned |
| Upload a blob | Denied | ✅ Permissions error |
| Read the storage account (control plane) | Denied | ✅ `AuthorizationFailed` on `storageAccounts/read` |

Evidence: [`scenario-5-08-verification.txt`](evidence/scenario-5-08-verification.txt)

## 8. Prevention

- Assign **data-plane** roles for data access; don't assume a control-plane role name like "Reader" covers data
- Scope data roles to the **container** when possible
- In production, set `allowSharedKeyAccess: false` so keys and account SAS can't bypass RBAC (kept `true` here to demonstrate the key path)
- Plan for locks when removing access: a CanNotDelete lock also blocks deleting role assignments in its scope

## Trade-offs and Notes

- Without Reader, Lab Tester can't browse to the storage account in the Azure portal; CLI, API, and Storage Explorer access still work. If portal access were required, Reader would be kept and documented.
- The first SAS test was invalid: on Windows, `az` runs through cmd.exe, which treated `&` in the URL as a command separator, so only part of the URL was sent. The request was anonymous, producing `PublicAccessNotPermitted`. The test was repeated with `Invoke-WebRequest`.
- The fake SAS used a signature of zeros; no real key or token was created or exposed.
