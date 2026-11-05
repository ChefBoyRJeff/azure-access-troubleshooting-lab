# Demo Script and Interview Guide

> This is a hands-on lab built in a personal Azure subscription. Describe it as lab or project experience, not production work.

## 1. 60-Second Summary

"I built an Azure lab that reproduces five real access-denied tickets: a role assigned at the wrong scope, the wrong lock type, a Deny policy, a policy remediation whose managed identity had no role, and a user who could see a storage account but couldn't read its data. For each one I captured the error, diagnosed it from evidence, fixed it with the least privilege that worked, proved the fix with a negative test, and wrote a root-cause analysis with sanitized output. The main skill is triage: the error code tells you which control blocked the request, so you don't waste time changing roles when the problem is a lock, a policy, or a credential."

## 2. 3–5 Minute Walkthrough

| Time | Section | What to say |
|---|---|---|
| 0:00 | Problem | "Access denied" has at least five different causes in Azure, and each needs a different fix. Changing roles won't fix a lock or a policy denial. |
| 0:30 | Architecture | Two resource groups (one deliberately "wrong"), a test user in a group, a CanNotDelete lock, a Deny and a Modify policy, a policy managed identity, and a private storage account. Baseline deployed with subscription-scope Bicep. |
| 1:15 | Method | Every scenario: symptom, hypothesis, diagnostics, evidence, root cause, remediation, verification (including a negative test), prevention. Always reproduce as the affected user. |
| 1:45 | Scenario deep dive (pick one) | **Scenario 4:** the policy definition declares Contributor, but the error showed the only failing action was `tags/write`. I granted Tag Contributor at resource group scope and proved it with a successful remediation. **Or Scenario 5:** Owner and Reader don't grant blob access; I fixed it with Storage Blob Data Reader on one container and proved writes were still blocked. |
| 3:30 | Lessons | My first test passed when it should have failed: it ran as the admin account. The Activity Log showed the real caller. Now I confirm the identity before trusting any access test. |
| 4:15 | Improvements | Move role assignments, locks, and policies into Bicep; disable shared key access in production; add a CI pipeline that runs what-if. |

## 3. Live Demo (About 5 Minutes, Non-Destructive)

Every demo below produces an error and changes nothing.

### Setup

**Admin terminal:**

```powershell
$st = "<your-storage-account-name>"
az account show --query user.name -o tsv
az lock list -g rg-access-lab-app --query "[].{name:name, level:level}" -o table
```

Confirm `lock-nodelete-app` (CanNotDelete) is listed before Demo B.

**Lab Tester terminal:**

```powershell
$env:AZURE_CONFIG_DIR = "$HOME\.azure-labtester"
$st = "<your-storage-account-name>"
az account show --query user.name -o tsv
```

Say: "First, I confirm which identity I'm testing as. My first test in this lab gave a false pass because it ran as admin."

### Demo A: Wrong Scope (Lab Tester)

```powershell
az group show -n rg-access-lab-other
```

Expected: `AuthorizationFailed`. Say: "The error gives me who, what action, and which scope. The user's group only has roles on the app resource group, and RBAC only inherits downward."

### Demo B: Lock Overrides RBAC (Admin, Owner)

```powershell
az network nsg delete -g rg-access-lab-app -n nsg-ticket-2
```

Expected: `ScopeLocked`. Only run this if Setup showed the lock. Say: "I'm Owner and still blocked. ScopeLocked means RBAC already allowed it, so changing roles won't help."

### Demo C: Policy Deny (Lab Tester)

```powershell
az network nsg create -g rg-access-lab-app -n nsg-demo
```

Expected: `RequestDisallowedByPolicy`. Say: "This user has permission; the request just doesn't meet a requirement. The fix is a compliant request with the costCenter tag, not weaker governance." Don't run it with the tag during a demo: the lock would keep the new NSG until teardown.

### Demo D: Control Plane vs. Data Plane

**Admin (Owner):**

```powershell
az storage blob download --account-name $st -c reports -n report-q3.txt -f "$env:TEMP\demo.txt" --auth-mode login --overwrite
```

Expected: a permissions error listing Storage ... Data roles. Say: "Owner manages the account, but blob data is a separate permission system."

**Lab Tester:** run the same command. Expected: success. Say: "The test user has only Storage Blob Data Reader on one container, and can read the file that Owner can't."

### Demo E: Authentication vs. Authorization (Either Terminal)

```powershell
$url = "https://$st.blob.core.windows.net/reports/report-q3.txt?sv=2023-11-03&sr=b&sp=r&st=2026-10-20T00:00:00Z&se=2026-10-21T00:00:00Z&spr=https&sig=" + ("A" * 43) + "%3D"
try { Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop } catch { $_.ErrorDetails.Message }
```

Expected: `AuthenticationFailed`. Say: "Azure doesn't know who I am, because the credential is invalid. That's authentication. Demo D was authorization: Azure knew exactly who I was and said no."

## 4. 10-Minute Deep Dive Outline

1. **Triage model (2 min):** the five error codes and the control behind each (see the README triage table)
2. **Scenario 1 (2 min):** wrong scope, `--include-groups`, the false-pass test, and how the Activity Log proved the caller
3. **Scenario 4 (2 min):** managed identities start with no permissions; portal vs. CLI behavior; Tag Contributor proven sufficient
4. **Scenario 5 (2 min):** control vs. data plane; keys bypass RBAC; the lock blocking removal of a role assignment; the 4-second unprotected window measured from the Activity Log
5. **IaC and drift (1 min):** Bicep tags replace existing tags; what-if before and after the fix
6. **Production changes (1 min):** see section 7

## 5. Design Decisions and Trade-offs

| Decision | Alternative | Why |
|---|---|---|
| Roles assigned to a group | Directly to the user | Easier to audit and remove; matches how organizations manage access |
| Network Contributor (Scenario 1) | Contributor | Ticket only needed networking; negative test proved storage creation was blocked |
| Add CanNotDelete before removing ReadOnly (Scenario 2) | Remove first | The resource group was never left unprotected |
| Compliant request (Scenario 3) | Exemption or Audit mode | Fixes the ticket without weakening the finance control |
| Tag Contributor (Scenario 4) | Contributor, as declared | The failing action was only `tags/write`; tested before closing |
| Container-scoped data role (Scenario 5) | Account-scoped, or a SAS | Read-only, limited to where the data lives, tied to a person |
| `allowSharedKeyAccess: true` | `false` | Kept to demonstrate the key path; would be `false` in production |

## 6. Hardest Problem

**A test that passed when it should have failed.** In Scenario 1, the "user can't create anything" test succeeded. Rather than accept it, I queried the Activity Log and found the caller was my admin account. The separate CLI profile had cached the admin sign-in. I fixed it with a device-code sign-in in a private browser window, and now I confirm the identity before every access test.

## 7. What I Would Change for Production

- Define role assignments, locks, and policy assignments in Bicep so access changes are reviewed in code
- Set `allowSharedKeyAccess: false` on storage accounts so keys and account SAS can't bypass RBAC
- Roll out Deny policies in stages (`DoNotEnforce` or Audit first) with notice to users
- Use Privileged Identity Management for just-in-time admin access instead of standing Owner
- Run what-if in a CI pipeline on every pull request
- Schedule access reviews to catch stale or over-broad assignments

## 8. Security and Cost

- All evidence is sanitized (IDs replaced with `<guid>`, domains with `contoso.onmicrosoft.com`), and a leak check runs before every commit
- No secrets or parameter files with real IDs are committed
- Running cost: under $0.01/month (one Standard LRS storage account with a few KB). A subscription-wide policy from my networking project blocks expensive resource types, and a $10 budget alert is in place.

## 9. Likely Interview Questions

**"A user says they can't access a resource. Walk me through it."**
Confirm the affected identity, then read the error code: it tells me whether it's authentication, RBAC, a lock, or a policy. For RBAC, list role assignments including group membership and check the scope. For storage, check whether a data-plane role is needed. Remember that changes take a few minutes and may need a fresh sign-in.

**"What's the difference between authentication and authorization?"**
Authentication is who you are; authorization is what you're allowed to do. In my lab, a fake SAS signature returned `AuthenticationFailed`, while a valid user without a data role returned `AuthorizationPermissionMismatch`. Different problems, different fixes.

**"Why can't an Owner read a blob?"**
Owner is a control-plane role. Reading blob data with Entra ID needs a data-plane role like Storage Blob Data Reader. Owner can still reach the data indirectly by listing account keys, which bypass RBAC. That's why production often disables shared key access.

**"When would you use a lock, a policy, or RBAC?"**
RBAC controls who can act. Policy controls what configurations are allowed. Locks protect resources from deletion or change, even for Owners. In Scenario 5, I found a CanNotDelete lock also blocks deleting role assignments in its scope.

**"How do you choose the right role?"**
Start from the failing action in the error, pick the narrowest built-in role that covers it at the narrowest scope, and prove it with a negative test. In Scenario 4, the definition said Contributor, but Tag Contributor was enough.

**"What happens to existing resources when you assign a Deny policy?"**
Nothing is deleted. They're marked non-compliant, and future updates to them without the required tag are denied. To fix them automatically, use a Modify policy with a remediation task, whose managed identity needs a role.

**"How did infrastructure as code interact with your manual fixes?"**
Bicep tags replace existing tags, so redeploying the original template would have removed the costCenter tag the Modify policy inherits from. What-if showed the removal before deployment, and I fixed the template before redeploying.

## 10. Honest Boundaries

- Say "in my lab" or "in this project," never "in production" or "at work"
- The misconfigurations were deliberate, so this demonstrates diagnosis and remediation technique, not handling a live outage
- Some theories are labeled as hypotheses in the RCAs; present them that way

## 11. Practice Questions With Model Answers

Each answer is about 45–60 seconds spoken. They draw on what was actually done in this lab; say "in my lab," not "in production."

### "A user says they can't access a storage account. Walk me through your first three steps."

"First, I confirm who's affected and reproduce it as that user, not as myself. In my lab, a test once passed only because it ran as my admin account, and the Activity Log showed the real caller. Second, I read the exact error code. `AuthenticationFailed` means a bad credential. `ScopeLocked` or `RequestDisallowedByPolicy` mean RBAC isn't the problem. `AuthorizationPermissionMismatch` on storage means they're signed in but missing a data role. Third, I list their role assignments including group membership, check each scope against where the data lives, and for blob access look specifically for a Storage Blob Data role, because Owner, Contributor, and Reader don't cover data. If I grant something, I have them sign in again before closing the ticket."

### "The error is `AuthorizationPermissionMismatch`, but the user says their manager gave them Contributor on the storage account yesterday."

"Contributor is a management-plane role: it manages the account but doesn't grant blob data access through Entra ID. It does include listing the account keys, so a key-based request would actually work, but I wouldn't recommend that. A key bypasses RBAC, can't be traced to a person, and gives full access to every container. I'd confirm the caller's identity and how they're authenticating, ask whether they need to read or also write, and assign Storage Blob Data Reader or Contributor on the specific container. Then I'd have them retest after a fresh sign-in, and flag the account-level Contributor for removal if it was only granted for this."

### "You need to remove a role assignment, but the delete fails with `ScopeLocked`. You're an Owner."

"`ScopeLocked` means a resource lock blocked it, and locks override RBAC, so being Owner doesn't help. A role assignment is itself a resource stored under that scope, so a CanNotDelete lock on the resource group blocks deleting it. I'd check locks at the target and every parent scope, confirm the lock type, and get approval for the change. Then I'd remove the lock, delete the assignment, and recreate the lock in one block, and verify both the assignments and the lock afterward. In my lab, the Activity Log showed the resource group was unprotected for about 4 seconds. Only roles with lock permissions, like Owner or User Access Administrator, can do this, so a Contributor would need to escalate."

### "A Modify policy's remediation failed with `Forbidden` on `tags/write`. The definition says the identity needs Contributor."

"The error names the exact failing action, `tags/write`, and the identity's object ID. I'd confirm that ID matches the policy assignment's managed identity, then check its roles. In my lab it had none, because the CLI doesn't grant one unless you pass `--role`. The definition declares Contributor, but the only action needed was `tags/write`, so I granted the built-in Tag Contributor at resource group scope. I created a new remediation task, since a failed one can't be restarted, and both resources were tagged. A custom role wasn't needed because a built-in role already covered it."

### "Someone fixes tags manually in the portal, and a week later a Bicep redeploy removes them again."

"That's configuration drift: the fix was made outside the source of truth. In Bicep, the `tags` property replaces a resource's tags rather than merging them, so any tag not in the template is removed on redeploy. I'd put the fix into the template, standardize tags through a shared parameter or module, and deploy only through a pipeline that runs what-if on every pull request. In my lab, what-if showed the `costCenter` tag being removed before anything was deployed, so I fixed the template first. Azure Policy adds a safety net: Deny to require tags on new resources, and Modify with remediation to fix existing ones."

## 12. Scenario 7: Management Groups and a Policy Initiative

**30-second version:** "I built a management group hierarchy, moved my subscription under it, and assigned an initiative of four built-in policies (allowed locations for resources and resource groups, a required `costCenter` tag, and tag inheritance) at the top management group. I rolled it out in audit mode first, then enforced it and reproduced the classic ticket: a Deny the user can't find on their subscription. The error named the management-group assignment. I exempted the two Azure-managed resource groups with a waiver and an expiry, remediated an existing resource with a Tag Contributor identity, and codified the baseline in Bicep at management-group scope."

**Numbers to quote (from the evidence):** Lab Tester could read the subscription and 7 resource groups via one Reader assignment two levels up; the first full compliance evaluation took about 45 minutes; the remediation task took about 17 minutes with ReEvaluateCompliance; enforcement of the new assignment and of the exemption was immediate.

### Practice questions

**"A deployment fails with RequestDisallowedByPolicy, but the subscription has no matching policy. Where do you look?"**
In the error first: it names the assignment and its scope. In my lab the scope was `/providers/Microsoft.Management/managementGroups/mg-lab`. Then I'd check the management group hierarchy above the subscription. Listing the subscription's own assignments didn't show the inherited one.

**"Why did your initiative include both 'Allowed locations' and 'Allowed locations for resource groups'?"**
Plain *Allowed locations* doesn't evaluate resource groups. My West US resource group was denied by the resource-group version.

**"Exemption or exclusion?"**
An exclusion (`notScopes`) removes the scope from evaluation entirely and leaves no record. An exemption keeps it evaluated, reports it as Exempt with a category (Waiver or Mitigated), a reason and an expiry, and can target one policy inside an initiative. I used exemptions for the two Azure-managed resource groups, only for the tag policy, so the location rules still applied to them.

**"Your Modify policy doesn't fix existing resources. Why?"**
Modify changes requests at create or update time. Existing resources need a remediation task, which runs as the assignment's managed identity, so that identity needs a role that covers the write. Tag Contributor was enough. I also ticked re-evaluate first, because the initial scan hadn't reached the resource yet, and Microsoft doesn't support that option at management-group scope.

**"How would you roll out a new Deny policy across 50 subscriptions safely?"**
Assign it at the management group with `DoNotEnforce`, read compliance to see who would be affected, fix or exempt with an expiry, communicate, then switch to enforced. Keep it in code with pinned definition versions.

### Honest boundaries for this scenario
The management group hierarchy and the subscription move were done in the portal, not in code, because a tenant-scope deployment needs deploy rights at the root. The cause of a second role assignment on the policy identity is a hypothesis (a portal edit granting the definition's Contributor), not confirmed.

## 13. Scenario 8: Entra Identity Lifecycle

**30-second version:** "On a free Entra ID P2 trial, I built a joiner-mover-leaver chain driven by one attribute. A dynamic group based on `department` scopes self-service password reset and assigns licenses, and a dynamic administrative unit limits a Helpdesk Administrator to Finance users. I also invited a B2B guest with Reader on a single resource group. A new hire was missing from the group because their department said `FIN`; Validate Rules against a known-good user proved it was the data, so I fixed the data rather than the rule."

**Numbers to quote (from the evidence):** first members joined the dynamic group 0.6 min after it was created; a department change removed the group membership after **21 s** and the license after **43 s**, logged as Microsoft services; 3 of 3 Finance members licensed through the group at the first check; Lab Tester reset a password inside the administrative unit and was denied outside it.

### Practice questions

**"A new hire isn't getting access that comes from a dynamic group. How do you troubleshoot?"**
I'd rule out processing delay first. In my lab other users had joined within a minute, so that was unlikely. Then I'd compare the user's attribute values with the rule, and run the portal's Validate Rules on the user next to a known-good user. It showed `department = FIN` against a rule needing `Finance`. I fixed the source data instead of widening the rule, and recommended a picklist at the source so it can't recur.

**"SSPR worked for a user without a license. Is that a problem?"**
Yes, it's a compliance problem rather than an outage. Microsoft documents that some tenant features can't block unlicensed users, but a license is still required for anyone meant to benefit. I closed it with group-based licensing on the same dynamic group, so the license and the SSPR scope follow the same attribute.

**"How do you prove the leaver process works?"**
Change the attribute and read the audit log. In my lab, moving a user from Finance to Sales produced *Remove member from group* after 21 seconds and *Change user license* after 43 seconds, both initiated by Microsoft services, with no manual step. A password reset attempt by an out-of-scope user was refused with the reason *"not a member of the password reset users group."*

**"How would you let a Finance help desk reset only Finance passwords?"**
An administrative unit containing the Finance users (dynamic, on the same attribute), with Helpdesk Administrator assigned at the AU's scope rather than tenant-wide. In my lab the delegated admin reset a Finance user's password and got *Insufficient privileges* for a Sales user. The portal only allowed the scoped assignment once the delegated admin had their own P1/P2 license.

**"A contractor needs read access to one project in Azure. What do you set up?"**
A B2B guest invitation, so they sign in with their own account and I never manage a password, plus Reader on that one resource group. I verified it from the guest's side: read worked, and a tag write failed with `AuthorizationFailed`. One thing I learned: redemption can overwrite the guest's display name, so look guests up by object ID, not by name.

**"Authentication or authorization: 'Your sign-in was successful but you don't have permission', error 53003?"**
Authentication succeeded; Conditional Access then blocked it, so it's a policy decision, not a credential problem. In my case the portal had picked the wrong tenant, where I'm a guest and the device wasn't registered. A tenant-specific URL fixed it.

### Honest boundaries for this scenario
This was built on a trial tenant with test users, not an HR-provisioned directory, so "HR data" was edited by hand. The *"I accepted but can't see anything"* guest ticket wasn't reproduced. Whether denied writes ever reach the Activity Log is an unconfirmed finding: none appeared within about 20 minutes. The portal's permission banner for administrative units was resolved by licensing the admins, but I didn't separately test which account's license the portal was checking.

## 14. Scenario 9: Key Vault With a Managed Identity

**30-second version:** "A VM reads its database password from Key Vault using a system-assigned managed identity, so there's no credential on the VM. I built it to fail layer by layer. From a private subnet the call timed out, which a service endpoint plus the vault firewall fixed. Then a 403 'Caller is not authorized', fixed with Key Vault Secrets User scoped to that one secret. I also showed 401s for a missing token, a wrong-audience token and a tampered token, and the vault firewall blocking me as Owner. I codified the network, vault and role in Bicep and checked it with what-if."

**Numbers to quote (from the evidence):** IMDS token issued even from the private subnet; the vault call timed out (curl exit 28); 200 thirty seconds after the role assignment; list and write still 403 `ForbiddenByRbac`; a deleted secret recovered in 2 seconds with the same value; final what-if 1 modify (noise) and 2 no change; total cost under $0.05.

### Practice questions

**"An app on a VM can't read a Key Vault secret. How do you troubleshoot?"**
Look at the failure type first. A timeout with no HTTP code is the network path. In my lab it was a private subnet with no route, fixed with a Key Vault service endpoint and a vault firewall rule for that subnet. A 401 is the token: missing, wrong audience or invalid. A 403 "Caller is not authorized" is RBAC: the identity needs a Key Vault data role. A 403 "Client address is not authorized" is the vault firewall. Then I check from the VM itself, through Run Command, not from my laptop, because my laptop is a different network and identity.

**"What's the difference between a 401 and a 403?"**
401 is authentication: the service can't trust who you are. I got it with no token (`AKV10000`), with a token issued for Azure Resource Manager instead of Key Vault (`AKV10022: Invalid audience`), and with a tampered token. 403 is authorization: it knows who you are and says no, either RBAC (`ForbiddenByRbac`) or the firewall.

**"Why use a managed identity instead of a service principal secret?"**
There's nothing to store, rotate or leak. The VM asks the local metadata endpoint for a token, and Azure handles the credential. It doesn't remove the need for authorization: the identity still needed a role, and I scoped it to one secret.

**"Why can't an Owner read secrets?"**
With the RBAC permission model, Owner is control plane only: it manages the vault, not its contents. Reading or writing secrets needs a data role like Key Vault Secrets Officer or Secrets User. A firewall can still block even then, as it did for me.

**"Service endpoint or private endpoint?"**
A service endpoint is free and needs no DNS changes; traffic goes over the Microsoft backbone and the vault firewall can allow the subnet, but the vault keeps its public IP. A private endpoint gives the vault a private IP in your VNet and lets you disable public access completely, at a small hourly cost and with private DNS to manage. I used a service endpoint here and a private endpoint for storage in another project.

**"Someone deleted a secret. What happens?"**
With soft delete, it's recoverable for the retention period, which I set to 7 days. The name is reserved meanwhile: creating a new secret with the same name returned Conflict. I recovered it, it came back with the original value in about 2 seconds, and the VM's secret-scoped role still worked without re-granting.

### Honest boundaries for this scenario
The VM was tested only through Run Command, not a real application. The VM and the secret value aren't in the Bicep, and the template was checked with what-if rather than deployed. The admin's laptop was allowed through the firewall with a /32 rule during the lab, which wouldn't be the production pattern.
