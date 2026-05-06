<#
.SYNOPSIS
Synchronizes Exchange Online mail contacts into the global Swyx phonebook.

.DESCRIPTION
Reads Exchange Online MailContacts, normalizes phone numbers, and synchronizes
them into the Swyx global phonebook using Swyx PowerShell cmdlets.

Display name format:
John Doe | Example Company
John Doe | Example Company (Mobile)

.PARAMETER WhatIf
Runs the synchronization in dry-run mode without changing Swyx entries.

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Sync-ExchangeToSwyx.ps1

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Sync-ExchangeToSwyx.ps1 -WhatIf

.NOTES
Project: Exchange Online to Swyx Phonebook Sync
License: MIT
#>

param(
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# CONFIGURATION
# =========================

# Exchange Online App-Only Authentication
$AppId = "<APP_ID>"
$CertificateThumbprint = "<CERTIFICATE_THUMBPRINT>"
$Organization = "<TENANT>.onmicrosoft.com"

# Paths
$BaseDirectory = "C:\System\Swyxware\Scripts"
$LogDirectory = Join-Path $BaseDirectory "Logs"
$StateFilePath = Join-Path $BaseDirectory "SwyxSyncState.json"

# Logging
$LogRetentionDays = 30
$Today = Get-Date -Format "yyyy-MM-dd"
$LogFile = Join-Path $LogDirectory "Sync-ExchangeToSwyx-$Today.log"

# Phone number normalization
$AddDefaultCountryCodeToLocalNumbers = $false
$DefaultCountryCode = "39"

# Display labels
$MobileSuffix = "(Mobil)"

# =========================
# LOGGING
# =========================

if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp - $Message"

    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Remove-ExpiredLogs {
    Get-ChildItem `
        -Path $LogDirectory `
        -Filter "Sync-ExchangeToSwyx-*.log" `
        -File `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays)
    } |
    ForEach-Object {
        try {
            Remove-Item -Path $_.FullName -Force
            Write-Log "Deleted old log file: $($_.Name)"
        }
        catch {
            Write-Log "Failed to delete old log file: $($_.Name)"
        }
    }
}

# =========================
# MODULES / VALIDATION
# =========================

function Import-RequiredModules {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Import-Module IpPbx -ErrorAction Stop
}

function Assert-RequiredCommands {
    $requiredCommands = @(
        "Connect-ExchangeOnline",
        "Disconnect-ExchangeOnline",
        "Get-MailContact",
        "Get-Contact",
        "Connect-IpPbx",
        "Get-IpPbxPhonebookEntry",
        "New-IpPbxPhonebookEntry",
        "Add-IpPbxPhoneBookEntry",
        "Update-IpPbxPhonebookEntry",
        "Remove-IpPbxPhoneBookEntry"
    )

    foreach ($commandName in $requiredCommands) {
        if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            throw "Required command '$commandName' is not available."
        }
    }
}

# =========================
# PHONE NORMALIZATION
# =========================

function Normalize-Phone {
    param(
        [AllowNull()]
        [string]$Number
    )

    if ([string]::IsNullOrWhiteSpace($Number)) {
        return $null
    }

    $normalized = $Number -replace "[^\d+]", ""

    if ($normalized.StartsWith("+")) {
        return $normalized
    }

    if ($normalized.StartsWith("00")) {
        return "+" + $normalized.Substring(2)
    }

    if ($normalized.StartsWith("0")) {
        if ($AddDefaultCountryCodeToLocalNumbers) {
            return "+$DefaultCountryCode" + $normalized.Substring(1)
        }

        return $normalized
    }

    return "+" + $normalized
}

# =========================
# STATE FILE
# =========================

function Get-SyncState {
    if (-not (Test-Path -Path $StateFilePath)) {
        return @()
    }

    try {
        $rawState = Get-Content -Path $StateFilePath -Raw

        if ([string]::IsNullOrWhiteSpace($rawState)) {
            return @()
        }

        $state = $rawState | ConvertFrom-Json

        if ($null -eq $state) {
            return @()
        }

        return @($state)
    }
    catch {
        Write-Log "Failed to read sync state file. Starting with empty state."
        return @()
    }
}

function Save-SyncState {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Entries
    )

    if (-not (Test-Path -Path $BaseDirectory)) {
        New-Item -Path $BaseDirectory -ItemType Directory -Force | Out-Null
    }

    @($Entries) |
        Select-Object Name, Number |
        ConvertTo-Json -Depth 5 |
        Set-Content -Path $StateFilePath -Encoding UTF8
}

# =========================
# EXCHANGE ONLINE
# =========================

function Connect-Exchange {
    Write-Log "Connecting to Exchange Online."

    Connect-ExchangeOnline `
        -AppId $AppId `
        -CertificateThumbprint $CertificateThumbprint `
        -Organization $Organization `
        -ShowBanner:$false | Out-Null

    Write-Log "Connected to Exchange Online."
}

function Get-SwyxDisplayName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [AllowNull()]
        [string]$Company
    )

    if (-not [string]::IsNullOrWhiteSpace($Company)) {
        return "$DisplayName | $Company"
    }

    return $DisplayName
}

function Get-DesiredSwyxEntriesFromExchange {
    Write-Log "Loading Exchange mail contacts."

    $mailContacts = Get-MailContact -ResultSize Unlimited
    $desiredEntries = New-Object System.Collections.Generic.List[object]

    foreach ($mailContact in $mailContacts) {
        try {
            $contact = Get-Contact -Identity $mailContact.Identity

            $baseName = Get-SwyxDisplayName `
                -DisplayName $contact.DisplayName `
                -Company $contact.Company

            $phone = Normalize-Phone -Number $contact.Phone
            $mobile = Normalize-Phone -Number $contact.MobilePhone

            if ($phone) {
                $desiredEntries.Add([pscustomobject]@{
                    Name        = $baseName
                    Number      = $phone
                    Description = ""
                })
            }

            if ($mobile) {
                $desiredEntries.Add([pscustomobject]@{
                    Name        = "$baseName $MobileSuffix"
                    Number      = $mobile
                    Description = ""
                })
            }
        }
        catch {
            Write-Log "Failed to process contact '$($mailContact.DisplayName)': $($_.Exception.Message)"
        }
    }

    $deduplicatedEntries = $desiredEntries |
        Sort-Object Name, Number, Description -Unique

    Write-Log "Collected $($deduplicatedEntries.Count) desired Swyx entries."

    return @($deduplicatedEntries)
}

# =========================
# SWYX
# =========================

function Connect-Swyx {
    Write-Log "Connecting to Swyx."
    Connect-IpPbx
    Write-Log "Connected to Swyx."
}

function Get-SwyxEntriesByName {
    $entries = Get-IpPbxPhonebookEntry -GlobalPhoneBook
    $entriesByName = @{}

    foreach ($entry in $entries) {
        if (-not $entriesByName.ContainsKey($entry.Name)) {
            $entriesByName[$entry.Name] = @()
        }

        $entriesByName[$entry.Name] += $entry
    }

    return $entriesByName
}

# =========================
# SYNC ENGINE
# =========================

function Sync-SwyxPhonebook {
    param(
        [array]$DesiredEntries = @(),
        [array]$PreviousStateEntries = @(),
        [switch]$WhatIf
    )

    $existingByName = Get-SwyxEntriesByName

    $desiredByName = @{}
    foreach ($desired in @($DesiredEntries)) {
        $desiredByName[$desired.Name] = $desired
    }

    # ADD / UPDATE
    foreach ($desired in @($DesiredEntries)) {
        $existingEntry = $null

        if ($existingByName.ContainsKey($desired.Name)) {
            $existingEntry = @($existingByName[$desired.Name])[0]
        }

        if (-not $existingEntry) {
            Write-Log "ADD: $($desired.Name) -> $($desired.Number)"

            if (-not $WhatIf) {
                $newEntry = New-IpPbxPhonebookEntry `
                    -Name $desired.Name `
                    -Number $desired.Number `
                    -Description "" `
                    -GlobalPhoneBook

                Add-IpPbxPhoneBookEntry -PhoneBookEntry $newEntry
            }

            continue
        }

        $needsUpdate = $false

        if ([string]$existingEntry.Number -ne [string]$desired.Number) {
            $existingEntry.Number = $desired.Number
            $needsUpdate = $true
        }

        if ([string]$existingEntry.Description -ne "") {
            $existingEntry.Description = ""
            $needsUpdate = $true
        }

        if ($needsUpdate) {
            Write-Log "UPDATE: $($desired.Name) -> $($desired.Number)"

            if (-not $WhatIf) {
                Update-IpPbxPhonebookEntry -PhoneBookEntry $existingEntry
            }
        }
    }

    # REMOVE
    # Only remove entries that were previously created by this sync.
    foreach ($previousEntry in @($PreviousStateEntries)) {
        if ($desiredByName.ContainsKey($previousEntry.Name)) {
            continue
        }

        if (-not $existingByName.ContainsKey($previousEntry.Name)) {
            continue
        }

        $entriesToRemove = @($existingByName[$previousEntry.Name]) |
            Where-Object {
                [string]$_.Number -eq [string]$previousEntry.Number
            }

        foreach ($entryToRemove in $entriesToRemove) {
            Write-Log "REMOVE: $($entryToRemove.Name) -> $($entryToRemove.Number)"

            if (-not $WhatIf) {
                Remove-IpPbxPhoneBookEntry `
                    -PhoneBookEntry $entryToRemove `
                    -Confirm:$false
            }
        }
    }
}

# =========================
# MAIN
# =========================

try {
    Remove-ExpiredLogs

    Write-Log "=== Sync started ==="
    Write-Log "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"

    Import-RequiredModules
    Connect-Exchange

    # Get-MailContact and Get-Contact are loaded after Connect-ExchangeOnline.
    Assert-RequiredCommands

    $previousStateEntries = @(Get-SyncState)
    $desiredEntries = @(Get-DesiredSwyxEntriesFromExchange)

    Connect-Swyx

    Sync-SwyxPhonebook `
        -DesiredEntries $desiredEntries `
        -PreviousStateEntries $previousStateEntries `
        -WhatIf:$WhatIf

    if (-not $WhatIf) {
        Save-SyncState -Entries $desiredEntries
    }

    Write-Log "=== Sync completed ==="
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)"
    throw
}
finally {
    try {
        Disconnect-ExchangeOnline `
            -Confirm:$false `
            -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # Ignore disconnect errors.
    }
}
