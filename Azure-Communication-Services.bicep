// Azure-Communication-Services.bicep
// Version: 1.0.0
// Date: 4/4/2025
// Author: Jody Ingram
// Pre-reqs: Contributor Access to valid Azure subscription
// Notes: This is a Bicep template that will be used to deploy Azure Communication Services. ACS can be used to extend email relay beyond the 10K limit, as well as extend PSTNs, etc.


metadata name = 'Communication Services'
metadata description = 'This module deploys a Communication Service'

param configurationSettings object
param namingSettings object
param taggingSettings object
param communicationServiceSetting object
param utcValue string = utcNow()

@description('Required. Name of the Communication Service.')
param name string = communicationServiceSetting.name

@description('Optional. Tags of the resource.')
param tags object = communicationServiceSetting.?tags ?? taggingSettings.tags

@description('Optional. The managed identity definition for this resource.')
param managedIdentities object = communicationServiceSetting.?managedIdentities ?? {}

@description('Optional. List of email Domain resource Ids.')
param linkedDomains array = communicationServiceSetting.?linkedDomains ?? []


var formattedUserAssignedIdentities = reduce(map((managedIdentities.?userAssignedResourceIds ?? []), (id) => { '${id}': {} }), {}, (cur, next) => union(cur, next)) // Converts the flat array to an object like { '${id1}': {}, '${id2}': {} }

var identity = !empty(managedIdentities) ? {
  type: (managedIdentities.?systemAssigned ?? false) ? (!empty(managedIdentities.?userAssignedResourceIds ?? {}) ? 'SystemAssigned, UserAssigned' : 'SystemAssigned') : (!empty(managedIdentities.?userAssignedResourceIds ?? {}) ? 'UserAssigned' : 'None')
  userAssignedIdentities: !empty(formattedUserAssignedIdentities) ? formattedUserAssignedIdentities : null
} : null


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
  

  @description('The name of the communication service.')
  output name string = communicationService.name
  
  @description('The resource ID of the communication service.')
  output resourceId string = communicationService.id
  
  @description('The resource group the communication service was deployed into.')
  output resourceGroupName string = resourceGroup().name
  
  @description('The location the communication service was deployed into.')
  output location string = communicationService.location
  
  @description('The principal ID of the system assigned identity.')
  output systemAssignedMIPrincipalId string = communicationService.?identity.?principalId ?? ''
