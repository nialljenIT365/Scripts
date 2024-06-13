﻿#description: Install Cisco Umbrella
#execution mode: Individual
#tags: abrdn, app install

#Modify Lines 9, 10, 12, 69

######################### CHANGE ME #########################
# Define Storage Account and File Share Name
$StorageAccountName = "<StorageAccountName>"
$FileShareName = "<StorageAccountName>"
# Define Application Name
$ApplicationName = "CiscoUmbrella"
$ApplicationInstaller1 = "cisco-secure-client-win-5.1.2.42-core-vpn-predeploy-k9.msi"
$ApplicationInstaller2 = "cisco-secure-client-win-5.1.2.42-umbrella-predeploy-k9.msi"
$ApplicationInstaller3 = "cisco-secure-client-win-5.1.2.42-iseposture-predeploy-k9.msi"
$ApplicationInstaller4 = "cisco-secure-client-win-5.1.2.42-dart-predeploy-k9.msi"
$ApplicationInstaller5 = "cisco-secure-client-win-5.1.2.42-posture-predeploy-k9.msi"
$ApplicationInstaller6 = "cisco-secure-client-win-5.1.2.42-sbl-predeploy-k9.msi "
######################### CHANGE ME #########################

######################### CHANGE ONLY IF REQUIRED IN DIFFERENT DESTINATION #########################
# Define Base Destination Path
$baseDestinationPath = "C:\Packages\Scripts\"
if (-Not (Test-Path $baseDestinationPath)) {
        New-Item -Path $baseDestinationPath -ItemType Directory
        Write-Output "Created destination directory at $destinationFolder"
    }
$logFileFolder = "C:\Packages\logs\"
if (-Not (Test-Path $logFileFolder)) {
        New-Item -Path $logFileFolder -ItemType Directory
        Write-Output "Created destination directory at $destinationFolder"
    }
######################### CHANGE ONLY IF REQUIRED IN DIFFERENT DESTINATION #########################


######################### SHOULD REMAIN CONSTANT #########################
# Define Source Folder
$SourcesFolder = "Files\"
# Combine Parts to Form the Full Source Path
$baseSourcePath = "\\$StorageAccountName.file.core.windows.net\$FileShareName\"
# Combine Base Paths with Application Name and Sources Folder
$sourceFolder = Join-Path -Path (Join-Path -Path $baseSourcePath -ChildPath $ApplicationName) -ChildPath $SourcesFolder
$destinationFolder = Join-Path -Path $baseDestinationPath -ChildPath $ApplicationName
# Include SourcesFolder in the destination path before the installer
$destinationWithSourcesFolder = Join-Path -Path $destinationFolder -ChildPath $SourcesFolder
# Define log file name and location
$logFileName = "$ApplicationName.log"
$logFileLocation = Join-Path -Path $logFileFolder -ChildPath $logFileName
# Ensure the log folder exists
if (-not (Test-Path -Path $logFileFolder)) {
    New-Item -Path $logFileFolder -ItemType Directory | Out-Null
}
######################### SHOULD REMAIN CONSTANT #########################


######################### FUNCTIONS #####################################
function Mount-AzureFileShare {
    param (
        [Parameter(Mandatory=$true)]
        [string]$StorageAccountName,

        [string]$UserName = "localhost\$StorageAccountName",
        [string]$DriveLetter = 'Z',
        [string]$FileShareName = 'test-fileshare'
    )

    $computerName = "$StorageAccountName.file.core.windows.net"
    $port = 445
    $key = $SecureVars.xxxxxxxx
    
    $connectTestResult = Test-NetConnection -ComputerName $computerName -Port $port

    if ($connectTestResult.TcpTestSucceeded) {
        # Save the password so the drive will persist on reboot
        $cmdKeyArgs = "/add:`"$computerName`" /user:`"$UserName`" /pass:`"$key`""
        cmd.exe /C "cmdkey $cmdKeyArgs"

        # Mount the drive
        New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root "\\$computerName\$FileShareName"

        Write-Output "Drive has been mounted successfully to \\$computerName\$FileShareName."
    } else {
        Write-Output "Unable to reach the Azure storage account via port 445. Check to make sure your organization or ISP is not blocking port 445, or use Azure P2S VPN, Azure S2S VPN, or Express Route to tunnel SMB traffic over a different port."
    }
}
function Copy-FolderToDestination {

    param(

        [Parameter(Mandatory=$true)]

        [string]$sourceFolder,

        [Parameter(Mandatory=$true)]

        [string]$destinationFolder

    )

    # Check if any input is an empty string
    if (-not $sourceFolder -or -not $destinationFolder) {
        Write-Output "One or more required inputs are empty. Please provide valid inputs."
        return
    }

    # Ensure the script runs with administrative privileges
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Output "This script requires administrative privileges."
        return
    }

    # Check if the source folder exists
    if (-Not (Test-Path $sourceFolder)) {
        Write-Output "The source folder at $sourceFolder does not exist. Please provide a valid source folder."
        return
    } else {
        Write-Output "Source folder at $sourceFolder is accessible."
    }

    # Check if the destination folder exists, create it if it does not
    if (-Not (Test-Path $destinationFolder)) {
        New-Item -Path $destinationFolder -ItemType Directory
        Write-Output "Created destination directory at $destinationFolder"
    }

    # Perform the folder copy
    try {
        Copy-Item -Path $sourceFolder -Destination $destinationFolder -Recurse -Force
        Write-Output "Folder copied successfully to $destinationFolder"
    } catch {
        Write-Error "Failed to copy folder: $_"
    }
}
function Delete-AzureFileShareCreds {
    param (
        [Parameter(Mandatory=$true)]
        [string]$StorageAccountName
    )

    $computerName = "$StorageAccountName.file.core.windows.net"
    cmd.exe /C "cmdkey /delete:$computerName"

}
function Delete-Sources {
    param (
        [Parameter(Mandatory=$true)]
        [string]$destinationFolder
    )

    # Ensure the script runs with administrative privileges
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Output "This script requires administrative privileges."
        return
    }

    try {
        # Check if the destination folder exists
        if (Test-Path -Path $destinationFolder) {
            # Force delete the destination folder and all contents
            Remove-Item -Path $destinationFolder -Recurse -Force
            Write-Output "Deleted the folder: $destinationFolder"
        } else {
            Write-Output "The specified folder does not exist: $destinationFolder"
            return
        }

        # Check if the parent folder is empty
        $parentFolder = Split-Path -Path $destinationFolder -Parent
        if ((Get-ChildItem -Path $parentFolder).Count -eq 0) {
            # Delete the parent folder if it is empty
            Remove-Item -Path $parentFolder -Force
            Write-Output "Deleted the empty parent folder: $parentFolder"
        }
    } catch {
        Write-Error "An error occurred: $_"
    }
}
######################### FUNCTIONS #####################################

# Mount Azure File Share
Mount-AzureFileShare -StorageAccountName $StorageAccountName -FileShareName $FileShareName

# Copy Relevent Source files
Copy-FolderToDestination -sourceFolder $sourceFolder -destinationFolder $destinationFolder

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller1 #########################
#Define additional paths that might be dynamically used in the arguments

# Combine Destination Folder with Application Installer to form the full install file path
$installFilePath = Join-Path -Path $destinationWithSourcesFolder -ChildPath $ApplicationInstaller1

# Construct the argument list dynamically using the variables
$argumentList = "/package `"$installFilePath`" /quiet /norestart /passive"
# Start the process with the specified file path and argument list
try {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "C:\Windows\System32\msiexec.exe"
    # Output install path to the console and log file
    $installPathMessage = "Install File Path is: $installFilePath"
    Write-Output $installPathMessage
    Write-Output $argumentList
    Out-File -FilePath $logFileLocation -Append -InputObject $installPathMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $argumentList

    $processInfo.Arguments = $argumentList
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    $process.WaitForExit()

    # Capture the output and error streams
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()

    # Write the output and error streams to the log file
    $stdOut | Out-File -FilePath $logFileLocation -Append
    $stdErr | Out-File -FilePath $logFileLocation -Append

    # Output installation completion message to the console and log file
    $completionMessage = "Installation process completed with exit code: $($process.ExitCode)"
    Write-Output $completionMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $completionMessage

} catch {
    Write-Error "An error occurred during installation: $_"
    $_.Exception.Message | Out-File -FilePath $logFileLocation -Append
}

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller1 #########################

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller2 #########################
#Define additional paths that might be dynamically used in the arguments

# Combine Destination Folder with Application Installer to form the full install file path
$installFilePath = Join-Path -Path $destinationWithSourcesFolder -ChildPath $ApplicationInstaller2

# Construct the argument list dynamically using the variables
$argumentList = "/package `"$installFilePath`" /quiet /norestart /passive"
# Start the process with the specified file path and argument list
try {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "C:\Windows\System32\msiexec.exe"
    # Output install path to the console and log file
    $installPathMessage = "Install File Path is: $installFilePath"
    Write-Output $installPathMessage
    Write-Output $argumentList
    Out-File -FilePath $logFileLocation -Append -InputObject $installPathMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $argumentList

    $processInfo.Arguments = $argumentList
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    $process.WaitForExit()

    # Capture the output and error streams
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()

    # Write the output and error streams to the log file
    $stdOut | Out-File -FilePath $logFileLocation -Append
    $stdErr | Out-File -FilePath $logFileLocation -Append

    # Output installation completion message to the console and log file
    $completionMessage = "Installation process completed with exit code: $($process.ExitCode)"
    Write-Output $completionMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $completionMessage

} catch {
    Write-Error "An error occurred during installation: $_"
    $_.Exception.Message | Out-File -FilePath $logFileLocation -Append
}

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller2 #########################

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller3 #########################
#Define additional paths that might be dynamically used in the arguments

# Combine Destination Folder with Application Installer to form the full install file path
$installFilePath = Join-Path -Path $destinationWithSourcesFolder -ChildPath $ApplicationInstaller3

# Construct the argument list dynamically using the variables
$argumentList = "/package `"$installFilePath`" /quiet /norestart /passive"
# Start the process with the specified file path and argument list
try {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "C:\Windows\System32\msiexec.exe"
    # Output install path to the console and log file
    $installPathMessage = "Install File Path is: $installFilePath"
    Write-Output $installPathMessage
    Write-Output $argumentList
    Out-File -FilePath $logFileLocation -Append -InputObject $installPathMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $argumentList

    $processInfo.Arguments = $argumentList
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    $process.WaitForExit()

    # Capture the output and error streams
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()

    # Write the output and error streams to the log file
    $stdOut | Out-File -FilePath $logFileLocation -Append
    $stdErr | Out-File -FilePath $logFileLocation -Append

    # Output installation completion message to the console and log file
    $completionMessage = "Installation process completed with exit code: $($process.ExitCode)"
    Write-Output $completionMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $completionMessage

} catch {
    Write-Error "An error occurred during installation: $_"
    $_.Exception.Message | Out-File -FilePath $logFileLocation -Append
}

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller3 #########################

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller4 #########################
#Define additional paths that might be dynamically used in the arguments

# Combine Destination Folder with Application Installer to form the full install file path
$installFilePath = Join-Path -Path $destinationWithSourcesFolder -ChildPath $ApplicationInstaller4

# Construct the argument list dynamically using the variables
$argumentList = "/package `"$installFilePath`" /quiet /norestart /passive"
# Start the process with the specified file path and argument list
try {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "C:\Windows\System32\msiexec.exe"
    # Output install path to the console and log file
    $installPathMessage = "Install File Path is: $installFilePath"
    Write-Output $installPathMessage
    Write-Output $argumentList
    Out-File -FilePath $logFileLocation -Append -InputObject $installPathMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $argumentList

    $processInfo.Arguments = $argumentList
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    $process.WaitForExit()

    # Capture the output and error streams
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()

    # Write the output and error streams to the log file
    $stdOut | Out-File -FilePath $logFileLocation -Append
    $stdErr | Out-File -FilePath $logFileLocation -Append

    # Output installation completion message to the console and log file
    $completionMessage = "Installation process completed with exit code: $($process.ExitCode)"
    Write-Output $completionMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $completionMessage

} catch {
    Write-Error "An error occurred during installation: $_"
    $_.Exception.Message | Out-File -FilePath $logFileLocation -Append
}

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller4 #########################

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller5 #########################
#Define additional paths that might be dynamically used in the arguments

# Combine Destination Folder with Application Installer to form the full install file path
$installFilePath = Join-Path -Path $destinationWithSourcesFolder -ChildPath $ApplicationInstaller5

# Construct the argument list dynamically using the variables
$argumentList = "/package `"$installFilePath`" /quiet /norestart /passive"
# Start the process with the specified file path and argument list
try {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "C:\Windows\System32\msiexec.exe"
    # Output install path to the console and log file
    $installPathMessage = "Install File Path is: $installFilePath"
    Write-Output $installPathMessage
    Write-Output $argumentList
    Out-File -FilePath $logFileLocation -Append -InputObject $installPathMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $argumentList

    $processInfo.Arguments = $argumentList
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    $process.WaitForExit()

    # Capture the output and error streams
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()

    # Write the output and error streams to the log file
    $stdOut | Out-File -FilePath $logFileLocation -Append
    $stdErr | Out-File -FilePath $logFileLocation -Append

    # Output installation completion message to the console and log file
    $completionMessage = "Installation process completed with exit code: $($process.ExitCode)"
    Write-Output $completionMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $completionMessage

} catch {
    Write-Error "An error occurred during installation: $_"
    $_.Exception.Message | Out-File -FilePath $logFileLocation -Append
}

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller5 #########################

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller6 #########################
#Define additional paths that might be dynamically used in the arguments

# Combine Destination Folder with Application Installer to form the full install file path
$installFilePath = Join-Path -Path $destinationWithSourcesFolder -ChildPath $ApplicationInstaller6

# Construct the argument list dynamically using the variables
$argumentList = "/package `"$installFilePath`" /quiet /norestart /passive"
# Start the process with the specified file path and argument list
try {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "C:\Windows\System32\msiexec.exe"
    # Output install path to the console and log file
    $installPathMessage = "Install File Path is: $installFilePath"
    Write-Output $installPathMessage
    Write-Output $argumentList
    Out-File -FilePath $logFileLocation -Append -InputObject $installPathMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $argumentList

    $processInfo.Arguments = $argumentList
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    $process.WaitForExit()

    # Capture the output and error streams
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()

    # Write the output and error streams to the log file
    $stdOut | Out-File -FilePath $logFileLocation -Append
    $stdErr | Out-File -FilePath $logFileLocation -Append

    # Output installation completion message to the console and log file
    $completionMessage = "Installation process completed with exit code: $($process.ExitCode)"
    Write-Output $completionMessage
    Out-File -FilePath $logFileLocation -Append -InputObject $completionMessage

} catch {
    Write-Error "An error occurred during installation: $_"
    $_.Exception.Message | Out-File -FilePath $logFileLocation -Append
}

######################### CHANGE ME APPLICATION INSTALL SECTION $ApplicationInstaller6 #########################

# UnMount Azure File Share and Delete Cached Credentials
Delete-AzureFileShareCreds -StorageAccountName $StorageAccountName

# Delete Sources
Delete-Sources -destinationFolder $destinationFolder