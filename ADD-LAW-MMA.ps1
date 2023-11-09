<#
.SYNOPSIS
This script is used to configure a workspace in the Microsoft Monitoring Agent (MMA).

This specific script will configure a workspace to connect to Log Analytics Workspace Name: <Security-Test>  ##UPDATE ACCORDINGLY##

.DESCRIPTION
The script does the following:
1. Creates a COM object for the AgentConfigManager.
2. Adds a cloud workspace using the provided workspace ID and key.
3. Reloads the configuration to apply the changes.

.VARIABLE Descriptions

.VARIABLE workspaceId
Line # 32
The ID of the workspace can be obtained from Azure Portal or your LAW Administrator if outside your permissions scope.

.VARIABLE workspaceKey
Line # 33
The key for the workspace can be obtained from Azure Portal or your LAW Administrator if outside your permissions scope. 
It is is populated the from the secure variable $SecureVars.workspaceKey defined in the Nerdio Manager keyvault by default.
Note: SET MANUALLY IF RUNNING OUTSIDE OF NERDIO CONTEXT.

.NOTES
Version: 1.0
Author: Niall Jennings
Creation Date: 26/10/2023
#>

# Variables
$workspaceId = "<ChangeMe>"
$workspaceKey = $SecureVars.workspaceKey

try {
    Write-Output "Attempting to create MMA object..."
    $mma = New-Object -ComObject 'AgentConfigManager.MgmtSvcCfg'
    Write-Output "Successfully created MMA object."
} catch {
    Write-Output "Failed to create MMA object. Error: $_"
    exit
}

try {
    Write-Output "Attempting to add cloud workspace..."
    $mma.AddCloudWorkspace($workspaceId, $workspaceKey)
    Write-Output "Successfully added cloud workspace."
} catch {
    Write-Output "Failed to add cloud workspace. Error: $_"
    exit
}

try {
    Write-Output "Attempting to reload configuration..."
    $mma.ReloadConfiguration()
    Write-Output "Successfully reloaded configuration."
} catch {
    Write-Output "Failed to reload configuration. Error: $_"
}