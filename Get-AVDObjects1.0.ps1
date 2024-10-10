# Function to return group members using Azure AD PowerShell
function Get-GroupMembersAzureAD {
    param (
        [string]$ObjectId,
        [string]$ParentGroupId = $null # Optional parameter to track the parent group ID
    )

    $result = @() # Initialize an array to hold results

    # Fetch the display name of the parent group, if ParentGroupId is not null
    $parentGroupName = if ($ParentGroupId) {
        (Get-AzureADGroup -ObjectId $ParentGroupId).DisplayName
    } else {
        $null
    }

    Write-Verbose "Fetching group members for GroupId: $ObjectId"
    # Fetching all members of the group
    $groupMembers = Get-AzureADGroupMember -ObjectId $ObjectId -All $true -ErrorVariable errGetGroupMember

    if ($errGetGroupMember) {
        Write-Warning "Error fetching group members for GroupId: $ObjectId. Error: $errGetGroupMember"
    }

    foreach ($member in $groupMembers) {
        try {
            if ($member.ObjectType -eq 'User') {
                Write-Verbose "Attempting to get user details for MemberId: $($member.ObjectId)"
                $userDetails = Get-AzureADUser -ObjectId $member.ObjectId -ErrorAction Stop
                $result += [PSCustomObject]@{
                    Id = $member.ObjectId
                    DisplayName = $userDetails.DisplayName
                    UserPrincipalName = $userDetails.UserPrincipalName
                    Type = "User"
                    ParentGroup = $parentGroupName
                }
            } elseif ($member.ObjectType -eq 'Group') {
                Write-Verbose "Attempting to get group details for MemberId: $($member.ObjectId)"
                $groupDetails = Get-AzureADGroup -ObjectId $member.ObjectId -ErrorAction Stop
                $result += [PSCustomObject]@{
                    Id = $member.ObjectId
                    DisplayName = $groupDetails.DisplayName
                    Type = "Group"
                    ParentGroup = $parentGroupName
                }

                # Recursively process subgroup members, passing current group ID as parent
                $subGroupMembers = Get-GroupMembersAzureAD -ObjectId $member.ObjectId -ParentGroupId $ObjectId
                $result += $subGroupMembers
            } else {
                Write-Warning "Failed to get details for MemberId: $($member.ObjectId). Type: Unknown"
                $result += [PSCustomObject]@{
                    Id = $member.ObjectId
                    Type = "Unknown"
                    ParentGroup = $parentGroupName
                }
            }
        } catch {
            Write-Warning "Failed to process MemberId: $($member.ObjectId)"
            $result += [PSCustomObject]@{
                Id = $member.ObjectId
                Type = "Error"
                ParentGroup = $parentGroupName
            }
        }
    }

    return $result
}

# Function to return group members using Microsoft Graph Powershell
function Get-GroupMembersMSGraph {
    param (
        [string]$ObjectId,
        [string]$ParentGroupId = $null # Optional parameter to track the parent group ID
    )

    $result = @() # Initialize an array to hold results

    # Fetch the display name of the parent group, if ParentGroupId is not null
    $parentGroupName = if ($ParentGroupId) {
        (Get-MgGroup -GroupId $ParentGroupId).DisplayName
    } else {
        $null
    }

    Write-Verbose "Fetching group members for GroupId: $ObjectId"
    $groupMemberIds = Get-MgGroupMember -GroupId $ObjectId -All:$true -ErrorVariable errGetGroupMember | Select-Object -ExpandProperty Id

    if ($errGetGroupMember) {
        Write-Warning "Error fetching group members for GroupId: $ObjectId. Error: $errGetGroupMember"
    }

    foreach ($memberId in $groupMemberIds) {
        try {
            Write-Verbose "Attempting to get user details for MemberId: $memberId"
            $userDetails = Get-MgUser -UserId $memberId -ErrorAction Stop
            $result += [PSCustomObject]@{
                Id = $memberId
                DisplayName = $userDetails.DisplayName
                UserPrincipalName = $userDetails.UserPrincipalName
                Type = "User"
                ParentGroup = $parentGroupName
            }
        } catch {
            try {
                Write-Verbose "Attempting to get group details for MemberId: $memberId"
                $groupDetails = Get-MgGroup -GroupId $memberId -ErrorAction Stop
                $result += [PSCustomObject]@{
                    Id = $memberId
                    DisplayName = $groupDetails.DisplayName
                    Type = "Group"
                    ParentGroup = $parentGroupName
                }

                # Recursively process subgroup members, passing current group ID as parent
                $subGroupMembers = Get-GroupMembersMSGraph -ObjectId $memberId -ParentGroupId $ObjectId
                $result += $subGroupMembers
            } catch {
                Write-Warning "Failed to get details for MemberId: $memberId. Type: Unknown"
                $result += [PSCustomObject]@{
                    Id = $memberId
                    Type = "Unknown"
                    ParentGroup = $parentGroupName
                }
            }
        }
    }

    return $result
}

# Function to test connection/permissions to on prem AD
function Test-ADConnection {
    try {
        # Check if the computer is part of a domain
        $computerSystem = Get-WmiObject Win32_ComputerSystem
        if ($computerSystem.PartOfDomain -eq $false) {
            Write-Host "Computer is not part of a domain."
            return $false
        }

        # Attempt to query AD
        Import-Module ActiveDirectory -ErrorAction Stop
        Get-ADComputer -Filter * -ErrorAction Stop | Out-Null

        # If successful, return true
        return $true
    } catch {
        # If an error occurs, return false
        Write-Host "Failed to connect to the domain or query AD: $_"
        return $false
    }
}

# Function to silently connect to Azure if not already authenticated
function Connect-AzureSilently {
    param (
        [string]$UserPrincipalName
    )

    $UserAccount = $UserPrincipalName
    $currentContext = Get-AzContext -ErrorAction SilentlyContinue
    # Connect to Azure if no current context found
    if (-not $currentContext -or -not $currentContext.Account -or $currentContext.Account.Id -ne $UserAccount) {
        [void] (Connect-AzAccount)
    }
}

# Function to silently connect to  Graph if not already authenticated
function Connect-MgGraphSilently {
    param (
        [string]$UserPrincipalName
    )
    try {
        # Attempt to get the current Microsoft Graph token
        $graphToken = Get-MgContext
    } catch {
        # If the token retrieval fails, initiate a silent connection
        $graphToken = $null
    }

    # If the token is null (not yet connected or expired), connect silently
    if (-not $graphToken) {
        # Connect to Microsoft Graph without interactive prompts
        Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All" -ErrorAction Stop -NoWelcome
    }
}

# Function to silently connect to Azure AD/Entra if not already authenticated
function Connect-AzureADSilently {
    param (
        [string]$UserPrincipalName
    )
    try {
        # Attempt to access a resource that requires authentication
        Get-AzureADUser -Top 1 -WarningAction SilentlyContinue | Out-Null
        $currentAzureADContext = Get-AzureADCurrentSessionInfo -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        if ($currentAzureADContext -eq $null -or $currentAzureADContext.Account.Id -ne $UserPrincipalName) {
            Connect-AzureAD -WarningAction SilentlyContinue | Out-Null
        }
    } catch {
        # If an error occurs, check if it's due to authentication or other issues
        Connect-AzureAD -WarningAction SilentlyContinue | Out-Null
    }
}

# Function to retrieve Tags from an Azure Object and add them as key pairs to a custom object for output to console or CSV
function Add-Tags {
    param (
        [PSCustomObject]$CustomObject,
        [hashtable]$Tags
    )

    if ($Tags) {
        foreach ($key in $Tags.Keys) {
            if (-not $CustomObject.PSObject.Properties[$key]) {
                $CustomObject | Add-Member -NotePropertyName $key -NotePropertyValue $Tags[$key]
            }
        }
    }

    return $CustomObject
}

function Get-AVDObjects {
    param (
        [string]$UserPrincipalName,
        [ValidateSet("Subscriptions","ResourceGroups","HostPools", "ApplicationGroups","WorkSpaces","PublishedApplications","PublishedDesktops","ApplicationGroupAssignments")]
        [string]$ObjectType,
        [ValidateSet("Console", "CSV")]
        [string]$OutputFormat = "Console",
        [ValidateSet("AzureAD", "MSGraph")]
        [string]$Auth
    )

    # Empty Array to hold Custom Objects
    $allCustomObjects = New-Object System.Collections.ArrayList
    # Current date to be passed to custom objects
    $currentDate = Get-Date -Format "MM/dd/yyyy"

    # START OF SUBSCRIPTION SECTON
    if ($ObjectType -eq "Subscriptions"){
        Connect-AzureSilently -UserPrincipalName $UserPrincipalName
        $subscriptions = Get-AzSubscription | Select-Object Name, Id, TenantId
        foreach ($subscription in $subscriptions) {
            #Subscription Custom Object
            $CustomObject = [PSCustomObject]@{
                DataLoadDate = $currentDate
                Type = "subscriptions"
                SubId = $subscription.Id
                Name = $subscription.Name
            }
            [void]$allCustomObjects.Add($CustomObject)
        }
    }

    # START OF ResourceGroups SECTION
    elseif ($ObjectType -eq "ResourceGroups"){
        Connect-AzureSilently -UserPrincipalName $UserPrincipalName
        $subscriptions = Get-AzSubscription | Select-Object Name, Id, TenantId
        foreach ($subscription in $subscriptions) {
            Set-AzContext -SubscriptionId $subscription.Id | Out-Null
            $resourcegroups = Get-AzResourceGroup
            foreach ($resourcegroup in $resourcegroups) {
                #Resource Group Custom Object
                $CustomObject = [PSCustomObject]@{
                    DataLoadDate = $currentDate
                    Type = (($resourcegroup.ResourceId -split '/')[-2])
                    SubId = $resourcegroup.ResourceId -split '/' | Select-Object -Index 2
                    Name = $resourcegroup.ResourceGroupName
                    ResourceId = $resourcegroup.ResourceId
                    Location = $resourcegroup.Location
            }
                $CustomObject = Add-Tags -CustomObject $CustomObject -Tags $resourcegroup.Tags
                [void]$allCustomObjects.Add($CustomObject)
            }
        }
    }

    # START OF Hostpools SECTION
    elseif ($ObjectType -eq "HostPools"){
        Connect-AzureSilently -UserPrincipalName $UserPrincipalName
        $subscriptions = Get-AzSubscription | Select-Object Name, Id, TenantId
        foreach ($subscription in $subscriptions) {
            Set-AzContext -SubscriptionId $subscription.Id | Out-Null
            $hostpools = Get-AzWvdHostPool
            foreach ($hostpool in $hostpools) {
                #Return Azure Object Data
                $AzResource = Get-AzResource -ResourceId $hostpool.Id
                #Hostpool Custom Object
                $CustomObject = [PSCustomObject]@{
                    DataLoadDate = $currentDate
                    Type = (($AzResource.ResourceId -split '/')[-2])
                    SubId = $AzResource.ResourceId -split '/' | Select-Object -Index 2
                    RGId = $AzResource.ResourceId -split '/' | Select-Object -Index 4
                    Name = $AzResource.Name
                    ResourceId = $AzResource.Id
                    Location = $AzResource.Location
                    HostPoolType = $hostpool.HostPoolType
                    MaxSessionLimit = $hostpool.MaxSessionLimit
               }
                # Add any existing resource tags to $CustomObject
                $CustomObject = Add-Tags -CustomObject $CustomObject -Tags $AzResource.Tags
                [void]$allCustomObjects.Add($CustomObject)
            }
        }
    }

    # START OF ApplicationGroups SECTION
    elseif ($ObjectType -eq "ApplicationGroups"){
        Connect-AzureSilently -UserPrincipalName $UserPrincipalName
        $subscriptions = Get-AzSubscription | Select-Object Name, Id, TenantId
        foreach ($subscription in $subscriptions) {
            Set-AzContext -SubscriptionId $subscription.Id | Out-Null
            $applicationgroups = Get-AzWvdApplicationGroup
            foreach ($applicationgroup in $applicationgroups) {
                #Return Azure Object Data
                $AzResource = Get-AzResource -ResourceId $applicationgroup.Id
                $CustomObject = [PSCustomObject]@{
                    DataLoadDate = $currentDate
                    Type = (($AzResource.ResourceId -split '/')[-2])
                    SubId = $AzResource.ResourceId -split '/' | Select-Object -Index 2
                    RGId = $AzResource.ResourceId -split '/' | Select-Object -Index 4
                    Name = $AzResource.Name
                    ResourceId = $AzResource.Id
                    Location = $AzResource.Location
                    ApplicationGroupType = $applicationgroup.ApplicationGroupType
                    HostPoolArmPath = $applicationgroup.HostPoolArmPath
                    WorkspaceArmPath = $applicationgroup.WorkspaceArmPath
                }
                # Add any existing resource tags to $CustomObject
                $CustomObject = Add-Tags -CustomObject $CustomObject -Tags $AzResource.Tags
                [void]$allCustomObjects.Add($CustomObject)
            }
        }
    }

    # START OF WorkSpaces SECTION
    elseif ($ObjectType -eq "WorkSpaces"){
        Connect-AzureSilently -UserPrincipalName $UserPrincipalName
        $subscriptions = Get-AzSubscription | Select-Object Name, Id, TenantId
        foreach ($subscription in $subscriptions) {
            Set-AzContext -SubscriptionId $subscription.Id | Out-Null
            $workspaces = Get-AzWvdWorkspace
            foreach ($workspace in $workspaces) {
                #Return Azure Object Data
                $AzResource = Get-AzResource -ResourceId $workspace.Id
                $CustomObject = [PSCustomObject]@{
                    DataLoadDate = $currentDate
                    Type = (($AzResource.ResourceId -split '/')[-2])
                    SubId = $AzResource.ResourceId -split '/' | Select-Object -Index 2
                    RGId = $AzResource.ResourceId -split '/' | Select-Object -Index 4
                    Name = $AzResource.Name
                    ResourceId = $AzResource.Id
                    Location = $AzResource.Location
                    Description = if ($workspace.Description) { $workspace.Description } else { "null" }
                    FriendlyName = if ($workspace.FriendlyName) { $workspace.FriendlyName } else { "null" }
                }
                # Add any existing resource tags to $CustomObject
                $CustomObject = Add-Tags -CustomObject $CustomObject -Tags $AzResource.Tags
                [void]$allCustomObjects.Add($CustomObject)
            }
        }
    }

    # START OF PublishedApplications SECTION
    elseif ($ObjectType -eq "PublishedApplications"){
        Connect-AzureSilently -UserPrincipalName $UserPrincipalName
        $subscriptions = Get-AzSubscription | Select-Object Name, Id, TenantId
        foreach ($subscription in $subscriptions) {
            Set-AzContext -SubscriptionId $subscription.Id | Out-Null
            $applicationgroups = Get-AzWvdApplicationGroup
            foreach ($applicationgroup in $applicationgroups) {
                #Return Azure Object Data
                $AzResource = Get-AzResource -ResourceId $applicationgroup.Id
                $publishedapplications = Get-AzWvdApplication -ResourceGroupName ($AzResource.ResourceId -split '/' | Select-Object -Index 4) -ApplicationGroupName $AzResource.Name
                foreach ($publishedapplication in $publishedapplications) {
                    $AzResource = Get-AzResource -ResourceId $publishedapplication.Id
                    $CustomObject = [PSCustomObject]@{
                    DataLoadDate = $currentDate
                    Type = (($AzResource.ResourceId -split '/')[-2])
                    SubId = $AzResource.ResourceId -split '/' | Select-Object -Index 2
                    RGId = $AzResource.ResourceId -split '/' | Select-Object -Index 4
                    Name = $AzResource.Name
                    ResourceId = $AzResource.Id
                    Location = $applicationgroup.Location
                    ApplicationGroupType = $applicationgroup.ApplicationGroupType
                    ApplicationGroupArmPath = $applicationgroup.Id
                    FriendlyName = if ($publishedapplication.FriendlyName) { $publishedapplication.FriendlyName } else { "null" }
                    }
                    [void]$allCustomObjects.Add($CustomObject)
                }
            }
        }
    }

    # START OF PublishedDesktops SECTION
    elseif ($ObjectType -eq "PublishedDesktops"){
        Connect-AzureSilently -UserPrincipalName $UserPrincipalName
        $subscriptions = Get-AzSubscription | Select-Object Name, Id, TenantId
        foreach ($subscription in $subscriptions) {
            Set-AzContext -SubscriptionId $subscription.Id | Out-Null
            $applicationgroups = Get-AzWvdApplicationGroup
            foreach ($applicationgroup in $applicationgroups) {
                $AzResource = Get-AzResource -ResourceId $applicationgroup.Id
                $publisheddesktops = Get-AzWvdDesktop -ResourceGroupName ($AzResource.ResourceId -split '/' | Select-Object -Index 4) -ApplicationGroupName $AzResource.Name
                foreach ($publisheddesktop in $publisheddesktops) {
                    $AzResource = Get-AzResource -ResourceId $publisheddesktop.Id
                    $CustomObject = [PSCustomObject]@{
                    DataLoadDate = $currentDate
                    Type = (($AzResource.ResourceId -split '/')[-2])
                    SubId = $AzResource.ResourceId -split '/' | Select-Object -Index 2
                    RGId = $AzResource.ResourceId -split '/' | Select-Object -Index 4
                    Name = $AzResource.Name
                    ResourceId = $AzResource.Id
                    Location = $applicationgroup.Location
                    ApplicationGroupType = $applicationgroup.ApplicationGroupType
                    ApplicationGroupArmPath = $applicationgroup.Id
                    FriendlyName = if ($publisheddesktop.FriendlyName) { $publisheddesktop.FriendlyName } else { "null" }
                    }
                    [void]$allCustomObjects.Add($CustomObject)
                }
            }
        }
    }

    # START OF ApplicationGroupAssignments SECTION
    elseif ($ObjectType -eq "ApplicationGroupAssignments"){
        if($Auth -eq $null -or $Auth -eq "MSGraph"){
            Connect-AzureSilently -UserPrincipalName $UserPrincipalName
            Connect-MgGraphSilently -UserPrincipalName $UserPrincipalName
            $subscriptions = Get-AzSubscription | Select-Object Name, Id, TenantId
            foreach ($subscription in $subscriptions) {
                Set-AzContext -SubscriptionId $subscription.Id | Out-Null
                $applicationgroups = Get-AzWvdApplicationGroup
                foreach ($applicationgroup in $applicationgroups) {
                    $HostPoolArmPath = $applicationgroup.HostPoolArmPath
                    $AzResource = Get-AzResource -ResourceId $applicationgroup.Id
                    $appgroupassignments = Get-AzRoleAssignment -Scope $applicationgroup.Id | Where-Object { $_.RoleDefinitionName -eq "Desktop Virtualization User" }
                    foreach ($appgroupassignment in $appgroupassignments){
                        if ($appgroupassignment.ObjectType -eq "Group"){
                            $members = Get-GroupMembersMSGraph -ObjectId $appgroupassignment.ObjectId
                            $members = $members | Where-Object { $_.Type -eq "User" }
                            foreach ($member in $members){
                                $CustomObject = [PSCustomObject]@{                              
                                    DataLoadDate = $currentDate
                                    SubName = $subscription.Name
                                    SubId = $subscription.Id
                                    ResourceName = if ($AzResource.ResourceName) { $AzResource.ResourceName } else { "null" }
                                    ParentHostpool = $HostPoolArmPath
                                    ResourceGroupName = if ($AzResource.ResourceGroupName) { $AzResource.ResourceGroupName } else { "null" }
                                    ResourceId = if ($appgroupassignment.Scope) { $appgroupassignment.Scope } else { "null" }
                                    GroupPath = $AzResource.ResourceName + "/" + (Get-MgGroup -GroupId $appgroupassignment.ObjectId).DisplayName + $(if ($member.Type -eq "User") { if ($member.ParentGroup) { "/" + $member.ParentGroup } } else { "/" + $member.ParentGroup + "/" + $member.DisplayName })
                                    Name = $member.UserPrincipalName
                                }
                                [void]$allCustomObjects.Add($CustomObject)
                            }
                        }
                        elseif ($appgroupassignment.ObjectType -eq "User"){
                            $CustomObject = [PSCustomObject]@{                              
                                DataLoadDate = $currentDate
                                SubName = $subscription.Name
                                SubId = $subscription.Id
                                ResourceName = if ($AzResource.ResourceName) { $AzResource.ResourceName } else { "null" }
                                ParentHostpool = $HostPoolArmPath
                                ResourceGroupName = if ($AzResource.ResourceGroupName) { $AzResource.ResourceGroupName } else { "null" }
                                ResourceId = if ($appgroupassignment.Scope) { $appgroupassignment.Scope } else { "null" }
                                GroupPath = $AzResource.ResourceName
                                Name = $appgroupassignment.SignInName
                            }
                            [void]$allCustomObjects.Add($CustomObject)
                        }
                    }
                }
            }
        }
        elseif($Auth -eq "AzureAD"){
            Connect-AzureSilently -UserPrincipalName $UserPrincipalName
            Connect-AzureADSilently -UserPrincipalName $UserPrincipalName
            $subscriptions = Get-AzSubscription | Select-Object Name, Id, TenantId
            foreach ($subscription in $subscriptions) {
                Set-AzContext -SubscriptionId $subscription.Id | Out-Null
                $applicationgroups = Get-AzWvdApplicationGroup
                foreach ($applicationgroup in $applicationgroups) {
                    $HostPoolArmPath = $applicationgroup.HostPoolArmPath
                    $AzResource = Get-AzResource -ResourceId $applicationgroup.Id
                    $appgroupassignments = Get-AzRoleAssignment -Scope $applicationgroup.Id | Where-Object { $_.RoleDefinitionName -eq "Desktop Virtualization User" }
                    foreach ($appgroupassignment in $appgroupassignments){
                        if ($appgroupassignment.ObjectType -eq "Group"){
                            $members = Get-GroupMembersAzureAD -ObjectId $appgroupassignment.ObjectId
                            $members = $members | Where-Object { $_.Type -eq "User" }
                                foreach ($member in $members){
                                    $CustomObject = [PSCustomObject]@{                              
                                        DataLoadDate = $currentDate
                                        SubName = $subscription.Name
                                        SubId = $subscription.Id
                                        ResourceName = if ($AzResource.ResourceName) { $AzResource.ResourceName } else { "null" }
                                        ParentHostpool = $HostPoolArmPath
                                        ResourceGroupName = if ($AzResource.ResourceGroupName) { $AzResource.ResourceGroupName } else { "null" }
                                        ResourceId = if ($appgroupassignment.Scope) { $appgroupassignment.Scope } else { "null" }                                             
                                        GroupPath = $AzResource.ResourceName + "/" + (Get-AzureADGroup -ObjectId $appgroupassignment.ObjectId).DisplayName + $(if ($member.Type -eq "User") { if ($member.ParentGroup) { "/" + $member.ParentGroup } } else { "/" + $member.ParentGroup + "/" + $member.DisplayName })
                                        Name = $member.UserPrincipalName
                                    }
                                    [void]$allCustomObjects.Add($CustomObject)
                            }
                        }
                        elseif ($appgroupassignment.ObjectType -eq "User"){
                            $CustomObject = [PSCustomObject]@{                              
                                DataLoadDate = $currentDate
                                SubName = $subscription.Name
                                SubId = $subscription.Id
                                ResourceName = if ($AzResource.ResourceName) { $AzResource.ResourceName } else { "null" }
                                ParentHostpool = $HostPoolArmPath
                                ResourceGroupName = if ($AzResource.ResourceGroupName) { $AzResource.ResourceGroupName } else { "null" }
                                ResourceId = if ($appgroupassignment.Scope) { $appgroupassignment.Scope } else { "null" }
                                GroupPath = $AzResource.ResourceName
                                Name = $appgroupassignment.SignInName
                            }
                            [void]$allCustomObjects.Add($CustomObject)
                        }
                    }
                }
            }
        }
    }

    # Output to CSV or Console
    switch ($OutputFormat) {
        "Console" {
            $allCustomObjects | Format-List
        }
        "CSV" {
            $currentDateForFile = Get-Date -Format "yyyyMMdd"
            $csvFileName = "$PSScriptRoot\$currentDateForFile-AVD-$ObjectType.csv"

            # Create a hash set to track the lowercase versions of property names
            $propertyNamesLower = @{}

            # Initialize an ordered dictionary to maintain the order of properties
            $propertyOrder = [System.Collections.Specialized.OrderedDictionary]::new()

            # Loop through each object and add its properties to the ordered dictionary
            foreach ($obj in $allCustomObjects) {
                foreach ($prop in $obj.PSObject.Properties) {
                    $lowerName = $prop.Name.ToLower()
                    if (-not $propertyNamesLower.ContainsKey($lowerName)) {
                        $propertyNamesLower[$lowerName] = $true
                        # Capitalize the first letter of each property name
                        $capitalizedName = (Get-Culture).TextInfo.ToTitleCase($lowerName)
                        $propertyOrder[$capitalizedName] = $true
                    }
                }
            }

            # Convert the ordered dictionary keys to an array for Select-Object
            $orderedPropertyNames = @($propertyOrder.Keys)

            try {
                $allCustomObjects |
                    Select-Object -Property $orderedPropertyNames |
                    Export-Csv -Path $csvFileName -NoTypeInformation -Force
                Write-Host "Data exported to CSV file: $csvFileName"
            } catch {
                Write-Host "An error occurred: $_"
            }
        }
    }
}
