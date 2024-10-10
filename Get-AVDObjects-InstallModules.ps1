# Install AzureAD Module
if (-not (Get-Module -ListAvailable -Name AzureAD)) {
    Install-Module -Name AzureAD -Force -Scope AllUsers
}

# Install Microsoft Graph PowerShell SDK
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module -Name Microsoft.Graph -Force -Scope AllUsers
}

# Install Az Module (for Azure PowerShell commands)
if (-not (Get-Module -ListAvailable -Name Az)) {
    Install-Module -Name Az -Force -Scope AllUsers
}

# Install Az.DesktopVirtualization Module (for Azure Virtual Desktop management)
if (-not (Get-Module -ListAvailable -Name Az.DesktopVirtualization)) {
    Install-Module -Name Az.DesktopVirtualization -Force -Scope AllUsers
}

# Install RSAT Tools for Active Directory (on Windows 10/11)
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    # Install RSAT components
    Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online
}

# Verify installation of all required modules
$modules = @('AzureAD', 'Microsoft.Graph', 'Az', 'Az.DesktopVirtualization', 'ActiveDirectory')

foreach ($module in $modules) {
    if (Get-Module -ListAvailable -Name $module) {
        Write-Host "$module is installed."
    } else {
        Write-Host "Error: $module is not installed."
    }
}
