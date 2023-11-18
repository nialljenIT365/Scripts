<#
.SYNOPSIS
This script is designed to configure a Log Analytics workspace in Azure by setting up a Data Collection Rule (DCR), associating it with a Virtual Machine (VM), and installing the Azure Monitor Agent (AMA) extension on the VM to facilitate data collection and logging.

.IMPORTANT WARNING: This script is provided freely and gladly shared. It is intended solely for testing and educational purposes. 
It are not recommended for use in production environments without thoroughly tested. Please be aware that using this script is at your own risk.

.DESCRIPTION
The script performs the following steps:

1. Sets up variables for Subscription ID, Log Analytics Workspace (LAW), Data Collection Rule (DCR), and Virtual Machine (VM) details.
2. Defines a logging function to write log entries with timestamps.
3. Attempts to import the Az.Monitor module necessary for creating the Data Collection Rule.
4. Constructs a JSON object representing the Data Collection Rule configuration, including data sources and destinations.
5. Writes the JSON object to a temporary file.
6. Verifies the temporary file's existence, and exits script execution if the file does not exist.
7. Attempts to create a new Data Collection Rule using the configuration in the temporary file.
8. Checks for the existence of the Azure Monitor Agent (AMA) extension on the VM, and installs it if not already present.
9. Verifies the creation of the Data Collection Rule, and creates a Rule Association between the DCR and the VM.
10. Verifies the Rule Association, logging the success or failure of each verification step.

.VARIABLE Descriptions

.VARIABLE SubId
Line # 85
The Subscription ID is populated the from Nerdio variable $AzureSubscriptionId by default.
Note: SET MANUALLY IF RUNNING OUTSIDE OF NERDIO CONTEXT

.VARIABLE LAWResourceGroup
Line # 89
The Resource Group of the Log Analytics Workspace.
Note: WILL NEED TO BE UPDATED BEFORE RUNNING SCRIPT

.VARIABLE LAWName
Line # 90
The name of the Log Analytics Workspace.
Note: WILL NEED TO BE UPDATED BEFORE RUNNING SCRIPT

.VARIABLE LAWId
Line # 91
The ID of the Log Analytics Workspace.
Note: WILL NEED TO BE UPDATED BEFORE RUNNING SCRIPT

.VARIABLE LAWRegion
Line # 93
The region of the Log Analytics Workspace.
Note: WILL NEED TO BE UPDATED BEFORE RUNNING SCRIPT

.VARIABLE DCRName
Line # 96
The name of the Data Collection Rule.
Note: WILL NEED TO BE UPDATED BEFORE RUNNING SCRIPT

.VARIABLER DCRDescription
Line # 97
The description of the Data Collection Rule.
Note: WILL NEED TO BE UPDATED BEFORE RUNNING SCRIPT

.VARIABLE DCRRegion
Line # 98
The region of the Data Collection Rule, which needs to be the same as the LAW region.

.VARIABLE DCRResourceGroup
Line # 100
The Resource Group for the Data Collection Rule is populated from the Nerdio variable $AzureResourceGroupName by default.
Note: SET MANUALLY IF RUNNING OUTSIDE OF NERDIO CONTEXT

.VARIABLE VirtualMachineName
Line # 104
The name of the target Virtual Machine is populated from the Nerdio variable $AzureVMName by default.
Note: SET MANUALLY IF RUNNING OUTSIDE OF NERDIO CONTEXT

.VARIABLE VMResourceGroup
Line # 106
The Resource Group of the target Virtual Machine is populated from the Nerdio variable $AzureResourceGroupName by default.
Note: SET MANUALLY IF RUNNING OUTSIDE OF NERDIO CONTEXT

.NOTES
Version: 1.0
Author: Niall Jennings
Creation Date: 1/11/2023
#>
# Variables
#$SubID in this script will leverage Nerdio variable $AzureSubscriptionId (set manually if running outside of Nerdio context)
$SubId = $AzureSubscriptionId


#The Target LAW variables can be obtained from Azure Portal or your LAW Administrator if outside your permissions scope. 
$LAWResourceGroup = "<ChangeMe>"
$LAWName = "<ChangeMe>"
$LAWId = "<ChangeMe>"
$LAWRegion = "<ChangeMe>"

#Data Collection Rule Details
#$DCRName and DCRDescription can be set manually to comply with Organization naming conventions.
$DCRName = "<ChangeMe>"
$DCRDescription = "<ChangeMe>"
#$DCRRegion Note: The Data Collection Rule needs to be created in the same Region as your LAW so it will mirror this variable.
$DCRRegion = $LAWRegion
#$DCRResourceGroup in this script will leverage Nerdio variable $AzureResourceGroupName and will mirror the target Resource Group the VM is being created in, it can be set manually if necessary.
$DCRResourceGroup = $AzureResourceGroupName

#Target Virtual Machine Details
#$VirtualMachineName in this script will leverage Nerdio variable $AzureVMName (Available when the script is associated with a VM), set it manually if running outside of Nerdio context
$VirtualMachineName = $AzureVMName
#$VMResourceGroup in this script will leverage Nerdio variable $AzureResourceGroupName and will mirror the target Resource Group the VM is being created in, set it manually if running outside of Nerdio context.
$VMResourceGroup = $AzureResourceGroupName

# Logging function
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp] [$Level] $Message"
}

# Import Az.Monitor module
try {
    Write-Log -Message "Attempting to import Az.Monitor module..." -Level INFO
    Import-Module Az.Monitor -ErrorAction Stop
    Write-Log -Message "Successfully imported Az.Monitor module." -Level INFO
} catch {
    Write-Log -Message "Failed to import Az.Monitor module. Error: $_" -Level ERROR
    exit
}

# Create the JSON object
$jsonObject = @{
    properties = @{
        dataSources = @{
            windowsEventLogs = @(
                @{
                    streams = @('Microsoft-Event')
                    xPathQueries = @(
                    "Security!*[System[(band(Keywords,13510798882111488))]]"
                    )
                    name = 'eventLogsDataSource'
                }
            )
        }
        destinations = @{
            logAnalytics = @(
                @{
                    workspaceResourceId = "/subscriptions/$SubId/resourceGroups/$LAWResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$LAWName"
                    workspaceId = "$LAWId"
                    name = "$LAWName"
                }
            )
        }
        dataFlows = @(
            @{
                streams = @('Microsoft-Event')
                destinations = @("$LAWName")
            }
        )
    }
}  | ConvertTo-Json -Depth 20

# Define the path to the temporary file in the $env:TEMP directory
$tempFilePath = Join-Path -Path $env:TEMP -ChildPath "sample.json"

# Write the JSON object to the temporary file
$jsonObject | Out-File $tempFilePath

# Verify the existence of the file
if (Test-Path -Path $tempFilePath) {
    Write-Output "File exists at $tempFilePath"
    
} else {
    Write-Output "File does not exist."
    exit
}

# Create New Data Collection Rule
try {
    Write-Log -Message "Attempting to create a new Data Collection Rule..." -Level INFO

    if (-not (Test-Path -Path $tempFilePath -ErrorAction SilentlyContinue)) {
        Write-Log -Message "File at $tempFilePath does not exist. Aborting Data Collection Rule creation." -Level ERROR
        exit
    }

    $existingDCR = Get-AzDataCollectionRule -ResourceGroupName $DCRResourceGroup -RuleName $DCRName -ErrorAction SilentlyContinue
    if ($existingDCR) {
        Write-Log -Message "Data Collection Rule $DCRName already exists. Skipping creation." -Level INFO
    } else {
        New-AzDataCollectionRule -Location $DCRRegion -ResourceGroupName $DCRResourceGroup -RuleName $DCRName -RuleFile $tempFilePath -Description $DCRDescription -ErrorAction Stop
        Write-Log -Message "Successfully created the Data Collection Rule." -Level INFO
    }
} catch {
    Write-Log -Message "Failed to create Data Collection Rule. Error: $_" -Level ERROR
    exit
}

# Install AMA Extension
try {
    Write-Log -Message "Checking if AMA Extension is already installed..." -Level INFO
    $existingExtension = Get-AzVMExtension -ResourceGroupName $AzureResourceGroupName -VMName $VirtualMachineName -Name AzureMonitorWindowsAgent -ErrorAction SilentlyContinue
    if ($existingExtension) {
        Write-Log -Message "AMA Extension is already installed. Skipping installation." -Level INFO
    } else {
        Write-Log -Message "Attempting to install AMA Extension..." -Level INFO
        Set-AzVMExtension -Name AzureMonitorWindowsAgent -ExtensionType AzureMonitorWindowsAgent -Publisher Microsoft.Azure.Monitor -ResourceGroupName $AzureResourceGroupName -VMName $VirtualMachineName -Location $AzureRegionName -TypeHandlerVersion "1.1" -EnableAutomaticUpgrade $true -ErrorAction Stop
        Write-Log -Message "Successfully installed AMA Extension." -Level INFO
    }
} catch {
    Write-Log -Message "Failed to install AMA Extension. Error: $_" -Level ERROR
    exit
}


# Verification
try {
    Write-Log -Message "Verifying the creation of Data Collection Rule..." -Level INFO
    $dcr = Get-AzDataCollectionRule -ResourceGroupName $DCRResourceGroup -RuleName $DCRName -ErrorAction Stop

    if ($dcr) {
        Write-Log -Message "Verification succeeded. Data Collection Rule $DCRName exists..creating Rule Association" -Level INFO
        $vmId = "/subscriptions/$SubId/resourceGroups/$VMResourceGroup/providers/Microsoft.Compute/virtualMachines/$VirtualMachineName"
        Write-Log -Message "VM ID is $vmId..creating Rule Association" -Level INFO
        $AssociationName = $VirtualMachineName + "-" + $DCRName
        Write-Log -Message "AssociationName is $AssociationName" -Level INFO
        
        # Verification of Rule Association
        $association = $dcr | Get-AzDataCollectionRuleAssociation
        if ($association | Where-Object { $_.Name -eq $AssociationName }) {
            Write-Log -Message "Rule Association $AssociationName already exists. No action taken." -Level INFO
        } else {
            Write-Log -Message "Rule Association $AssociationName does not exist. Creating Rule Association..." -Level INFO
            New-AzDataCollectionRuleAssociation -DataCollectionRuleId $dcr.Id -TargetResourceId $vmId -AssociationName $AssociationName -ErrorAction Stop
            Write-Log -Message "Successfully created Rule Association $AssociationName. Verifying..." -Level INFO

            # Verify Rule Association
            $association = $dcr | Get-AzDataCollectionRuleAssociation
            if ($association | Where-Object { $_.Name -eq $AssociationName }) {
                Write-Log -Message "Verification succeeded. Rule Association $AssociationName exists." -Level INFO
            } else {
                Write-Log -Message "Verification failed. Rule Association $AssociationName does not exist." -Level ERROR
                exit
            }
        }
    } else {
        Write-Log -Message "Verification failed. Data Collection Rule $DCRName does not exist." -Level ERROR
        exit
    }
} catch {
    Write-Log -Message "Failed to verify the existence of Data Collection Rule or Rule Association. Error: $_" -Level ERROR
    exit
}