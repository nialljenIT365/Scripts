#Requires -Version 5.1
<#
.SYNOPSIS
    Applies registry settings to disable Windows content delivery / suggestions
    and reduce menu animation delay.

.DESCRIPTION
    Sets the following registry values:
      - Disables Start menu app suggestions (SubscribedContent-338393)
      - Disables tips, tricks & suggestions notifications (SubscribedContent-353696)
      - Disables lock-screen Spotlight suggestions (SubscribedContent-338388)
      - Disables lock-screen app suggestions (SubscribedContent-338389)
      - Disables taskbar/system pane suggestions (SystemPaneSuggestionsEnabled)
      - Sets menu show delay to 0 ms for a snappier UI

.NOTES
    Run as the target user (no elevation required — all keys are under HKCU).
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# ---------------------------------------------------------------------------
# Registry entries to apply
# ---------------------------------------------------------------------------
$RegistrySettings = @(
    @{
        HivePath      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        KeyName       = "SubscribedContent-338393Enabled"
        PropertyType  = "DWORD"
        PropertyValue = 0
        Description   = "Disable Start menu app suggestions"
    },
    @{
        HivePath      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        KeyName       = "SubscribedContent-353696Enabled"
        PropertyType  = "DWORD"
        PropertyValue = 0
        Description   = "Disable tips, tricks & suggestions notifications"
    },
    @{
        HivePath      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        KeyName       = "SubscribedContent-338388Enabled"
        PropertyType  = "DWORD"
        PropertyValue = 0
        Description   = "Disable lock-screen Spotlight suggestions"
    },
    @{
        HivePath      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        KeyName       = "SubscribedContent-338389Enabled"
        PropertyType  = "DWORD"
        PropertyValue = 0
        Description   = "Disable lock-screen app suggestions"
    },
    @{
        HivePath      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        KeyName       = "SystemPaneSuggestionsEnabled"
        PropertyType  = "DWORD"
        PropertyValue = 0
        Description   = "Disable taskbar / system pane suggestions"
    },
    @{
        HivePath      = "HKCU:\Control Panel\Desktop"
        KeyName       = "MenuShowDelay"
        PropertyType  = "String"
        PropertyValue = "0"
        Description   = "Set menu show delay to 0 ms"
    }
)

# ---------------------------------------------------------------------------
# Helper — map friendly type name to the value New-ItemProperty expects
# ---------------------------------------------------------------------------
function Resolve-PropertyType {
    param([string]$Type)
    switch ($Type.ToUpper()) {
        "DWORD"  { return "DWord"  }
        "QWORD"  { return "QWord"  }
        "STRING" { return "String" }
        "BINARY" { return "Binary" }
        "MULTI"  { return "MultiString" }
        "EXPAND" { return "ExpandString" }
        default  { return $Type }
    }
}

# ---------------------------------------------------------------------------
# Apply settings
# ---------------------------------------------------------------------------
$successCount = 0
$failCount    = 0

foreach ($setting in $RegistrySettings) {

    $regType = Resolve-PropertyType -Type $setting.PropertyType

    Write-Host "  -> $($setting.Description)" -ForegroundColor Cyan
    Write-Verbose "     Path  : $($setting.HivePath)"
    Write-Verbose "     Name  : $($setting.KeyName)"
    Write-Verbose "     Type  : $regType  Value: $($setting.PropertyValue)"

    try {
        # Create the key path if it does not already exist
        if (-not (Test-Path -LiteralPath $setting.HivePath)) {
            if ($PSCmdlet.ShouldProcess($setting.HivePath, "Create registry key")) {
                New-Item -Path $setting.HivePath -Force | Out-Null
            }
        }

        if ($PSCmdlet.ShouldProcess("$($setting.HivePath)\$($setting.KeyName)", "Set registry value")) {
            Set-ItemProperty -LiteralPath $setting.HivePath `
                             -Name        $setting.KeyName `
                             -Value       $setting.PropertyValue `
                             -Type        $regType `
                             -Force
        }

        Write-Host "     [OK]" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Warning "     [FAILED] $($_.Exception.Message)"
        $failCount++
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Done. $successCount setting(s) applied, $failCount failed." `
           -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })

if ($failCount -gt 0) {
    Write-Host "Re-run with -Verbose for details, or check the warnings above." `
               -ForegroundColor Yellow
}
