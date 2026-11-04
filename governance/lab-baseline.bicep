// P4 Scenario 7: the governance baseline built in the portal + CLI, codified.
// Written from the live export (governance/export/, gitignored by *.json).
// Deploys at MANAGEMENT GROUP scope:
//   1. the initiative "Lab governance baseline" (4 built-in policies, 2 initiative parameters)
//   2. its assignment at the management group, with a system-assigned identity
//   3. Tag Contributor for that identity at the management group (least privilege, proven in Scenario 4 and 7)
// Not deployed here (documented in docs/scenario-7-management-groups-initiative.md):
//   the management group hierarchy itself (tenant-scope deployment), the subscription move,
//   and the time-bound exemptions for Azure-managed resource groups.
targetScope = 'managementGroup'

@description('Initiative resource name. Matches the portal-created definition so what-if compares like with like.')
param initiativeName string

@description('Assignment resource name.')
param assignmentName string = 'lab-baseline'

@description('Region for the assignment\'s managed identity metadata.')
param identityLocation string

@description('Regions allowed for resources and resource groups.')
param allowedLocations array

@description('Tag required on resource groups and inherited by resources.')
param tagName string

@description('Default = enforced (Deny and Modify act). DoNotEnforce = audit only, the safe rollout mode.')
@allowed([
  'Default'
  'DoNotEnforce'
])
param enforcementMode string = 'Default'

var builtIn = {
  allowedLocations: 'e56962a6-4747-49cd-b67b-bf8b01975c4c'
  allowedLocationsRg: 'e765b5de-1225-4ba3-bd56-1ac6695af988'
  requireTagRg: '96670d01-0a4d-4649-9c89-2d3abc0a5025'
  inheritTagFromRg: 'ea3f2387-9b95-492a-a190-fcdc54f7b070'
}
var tagContributorRoleId = '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'

resource initiative 'Microsoft.Authorization/policySetDefinitions@2025-01-01' = {
  name: initiativeName
  properties: {
    displayName: 'Lab governance baseline'
    description: 'Allowed locations and costCenter tagging for lab resource groups and resources.'
    policyType: 'Custom'
    version: '1.0.0' // policy versioning (semantic version of this initiative)
    metadata: {
      category: 'Lab'
    }
    parameters: {
      allowedLocations: {
        type: 'Array'
        defaultValue: allowedLocations
        metadata: {
          displayName: 'Allowed locations'
          assignPermissions: false // portal default, declared to keep what-if quiet
          portalReview: false
        }
      }
      tagName: {
        type: 'String'
        defaultValue: tagName
        metadata: {
          displayName: 'Tag name'
          assignPermissions: false // portal default, declared to keep what-if quiet
          portalReview: false
        }
      }
    }
    policyDefinitions: [
      {
        // "Allowed locations" skips resource groups; the next entry covers them (exam trap).
        policyDefinitionReferenceId: 'Allowed locations_1'
        definitionVersion: '1.1.*' // pinned major.minor, as the portal set it
        policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', builtIn.allowedLocations)
        parameters: {
          listOfAllowedLocations: {
            value: '[parameters(\'allowedLocations\')]'
          }
        }
      }
      {
        policyDefinitionReferenceId: 'Allowed locations for resource groups_1'
        definitionVersion: '1.1.*' // pinned major.minor, as the portal set it
        policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', builtIn.allowedLocationsRg)
        parameters: {
          listOfAllowedLocations: {
            value: '[parameters(\'allowedLocations\')]'
          }
        }
      }
      {
        policyDefinitionReferenceId: 'Require a tag on resource groups_1'
        definitionVersion: '1.0.*' // pinned major.minor, as the portal set it
        policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', builtIn.requireTagRg)
        parameters: {
          tagName: {
            value: '[parameters(\'tagName\')]'
          }
        }
      }
      {
        policyDefinitionReferenceId: 'Inherit a tag from the resource group if missing_1'
        definitionVersion: '1.0.*' // pinned major.minor, as the portal set it
        policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', builtIn.inheritTagFromRg)
        parameters: {
          tagName: {
            value: '[parameters(\'tagName\')]'
          }
        }
      }
    ]
  }
}

resource assignment 'Microsoft.Authorization/policyAssignments@2025-01-01' = {
  name: assignmentName
  location: identityLocation
  identity: {
    type: 'SystemAssigned' // needed by the Modify policy (inherit tag) for remediation
  }
  properties: {
    displayName: 'Lab governance baseline (mg-lab)'
    policyDefinitionId: initiative.id
    definitionVersion: '1.*.*' // follow minor/patch updates of the initiative, not a new major version
    enforcementMode: enforcementMode
  }
}

// The portal would grant the role listed in the definition (Contributor). Tag Contributor was enough (Scenario 4 and 7).
resource identityRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managementGroup().id, assignment.id, tagContributorRoleId)
  properties: {
    principalId: assignment.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: tenantResourceId('Microsoft.Authorization/roleDefinitions', tagContributorRoleId)
  }
}

output assignmentId string = assignment.id
output initiativeId string = initiative.id
