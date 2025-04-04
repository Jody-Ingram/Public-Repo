/* Azure-Communication-Services.bicep
Version: 1.0.0
Date: 4/4/2025
Author: Jody Ingram
Pre-reqs: Contributor Access to valid Azure subscription
Notes: This is a Bicep template that will be used to deploy Azure Communication Services. ACS can be used to extend email relay beyond the 10K limit, as well as extend PSTNs, etc. */


@metadata({
  name: 'Communication Services'
  description: 'This module deploys a Communication Service'
})

/* -----------------------------
   Parameters - External Inputs
-------------------------------- */
@description('Generic configuration settings for this module.')
param configurationSettings object

@description('Naming conventions and settings.')
param namingSettings object

@description('Global tagging configuration.')
param taggingSettings object

@description('Specific settings for the Communication Service.')
param communicationServiceSetting object

@description('Current UTC time, defaults to now.')
param utcValue string = utcNow()

/* -----------------------------
   Parameters - Resource Specific
-------------------------------- */
@description('Required. Name of the Communication Service.')
param name string = communicationServiceSetting.name

@description('Optional. Tags for the resource.')
param tags object = empty(communicationServiceSetting.tags) ? taggingSettings.tags : communicationServiceSetting.tags

@description('Optional. Managed identity configuration for the resource.')
param managedIdentities object = communicationServiceSetting.managedIdentities ?? {}

@description('Optional. List of email domain resource IDs to link.')
param linkedDomains array = communicationServiceSetting.linkedDomains ?? []

/* -----------------------------
   Variables - Identity Handling
-------------------------------- */
// Transform userAssignedResourceIds array into the required object format
var userAssignedIds = managedIdentities.userAssignedResourceIds ?? []
var formattedUserAssignedIdentities = reduce(
  map(userAssignedIds, (id) => {
    '${id}': {}
  }),
  {},
  (cur, next) => union(cur, next)
)

// Determine identity type
var identityType = empty(managedIdentities)
  ? 'None'
  : managedIdentities.systemAssigned
    ? (!empty(userAssignedIds) ? 'SystemAssigned, UserAssigned' : 'SystemAssigned')
    : (!empty(userAssignedIds) ? 'UserAssigned' : 'None')

// Final identity object
var identity = identityType != 'None' ? {
  type: identityType
  userAssignedIdentities: empty(formattedUserAssignedIdentities) ? null : formattedUserAssignedIdentities
} : null

/* -----------------------------
   Resource - Communication Service
-------------------------------- */
resource communicationService 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: name
  location: 'global'
  identity: identity
  tags: tags
  properties: {
    dataLocation: 'United States'
    linkedDomains: linkedDomains
  }
}

/* -----------------------------
   Outputs
-------------------------------- */
@description('The name of the communication service.')
output name string = communicationService.name

@description('The resource ID of the communication service.')
output resourceId string = communicationService.id

@description('The resource group the communication service was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The location the communication service was deployed into.')
output location string = communicationService.location

@description('The principal ID of the system assigned identity.')
output systemAssignedMIPrincipalId string = communicationService.identity?.principalId ?? ''
