<#
.SYNOPSIS
Synchronizes Exchange Online mail contacts into the global Swyx phonebook.

.DESCRIPTION
Reads mail contacts from Exchange, normalizes their phone numbers, and creates,
updates, or removes the Swyx phonebook entries managed by this script.

.PARAMETER WhatIf
Runs the synchronization in dry-run mode without changing any Swyx entries.

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Sync-ExchangeToSwyx.ps1

.EXAMPLE
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Sync-ExchangeToSwyx.ps1 -WhatIf

.NOTES
Author: Manuel J. Mahr
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
$Marker = "[EXO-SYNC]"
$LogBasePath = "C:\System\Swyxware\Scripts\Logs\SwyxSync.log"
$LogRetentionDays = 2
$AddDefaultCountryCodeToLocalNumbers = $false
$DefaultCountryCode = "39"

# =========================
# LOGGING
# =========================
$logDirectory = Split-Path -Path $LogBasePath -Parent
$logFileName = [System.IO.Path]::GetFileNameWithoutExtension($LogBasePath)
$logExtension = [System.IO.Path]::GetExtension($LogBasePath)
$today = Get-Date -Format "yyyy-MM-dd"
$LogFile = Join-Path $logDirectory "$logFileName`_$today$logExtension"

if (-not (Test-Path -Path $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
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
    Get-ChildItem -Path $logDirectory -Filter "$logFileName*_*.log" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } |
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

function Assert-RequiredCommands {
    $requiredCommands = @(
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
            throw "Required command '$commandName' is not available in the current session."
        }
    }
}

function Normalize-Phone {
    param(
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

function Get-DesiredSwyxEntriesFromExchange {
    Write-Log "Loading Exchange mail contacts."

    $mailContacts = Get-MailContact -ResultSize Unlimited
    $desiredEntries = New-Object System.Collections.Generic.List[object]

    foreach ($mailContact in $mailContacts) {
        try {
            $contact = Get-Contact -Identity $mailContact.Identity

            $displayName = $contact.DisplayName
            $company = $contact.Company
            $email = [string]$mailContact.PrimarySmtpAddress
            $description = "$company | $email | $Marker"

            $phone = Normalize-Phone -Number $contact.Phone
            $mobile = Normalize-Phone -Number $contact.MobilePhone

            if ($phone) {
                $desiredEntries.Add([pscustomobject]@{
                    Name        = $displayName
                    Number      = $phone
                    Description = $description
                })
            }

            if ($mobile) {
                $desiredEntries.Add([pscustomobject]@{
                    Name        = "$displayName (Mobil)"
                    Number      = $mobile
                    Description = $description
                })
            }
        }
        catch {
            Write-Log "Failed to read contact '$($mailContact.DisplayName)': $($_.Exception.Message)"
        }
    }

    $deduplicatedEntries = $desiredEntries | Sort-Object Name, Number, Description -Unique
    Write-Log "Collected $($deduplicatedEntries.Count) desired Swyx entries from Exchange."

    return @($deduplicatedEntries)
}

function Get-ManagedSwyxEntries {
    Write-Log "Connecting to Swyx."
    Connect-IpPbx
    Write-Log "Connected to Swyx."

    $existingEntries = Get-IpPbxPhonebookEntry -GlobalPhoneBook |
        Where-Object { $_.Description -like "*$Marker*" }

    Write-Log "Found $($existingEntries.Count) managed Swyx entries."
    return @($existingEntries)
}

function Sync-SwyxPhonebook {
    param(
        [Parameter(Mandatory = $true)]
        [array]$DesiredEntries,

        [Parameter(Mandatory = $true)]
        [array]$ExistingEntries,

        [switch]$WhatIf
    )

    $existingByName = @{}
    foreach ($entry in $ExistingEntries) {
        $existingByName[$entry.Name] = $entry
    }

    foreach ($desired in $DesiredEntries) {
        if (-not $existingByName.ContainsKey($desired.Name)) {
            Write-Log "ADD: $($desired.Name) -> $($desired.Number)"

            if (-not $WhatIf) {
                $newEntry = New-IpPbxPhonebookEntry `
                    -Name $desired.Name `
                    -Number $desired.Number `
                    -Description $desired.Description `
                    -GlobalPhoneBook

                Add-IpPbxPhoneBookEntry -PhoneBookEntry $newEntry
            }

            continue
        }

        $existing = $existingByName[$desired.Name]
        $needsUpdate = $false

        if ([string]$existing.Number -ne [string]$desired.Number) {
            $existing.Number = $desired.Number
            $needsUpdate = $true
        }

        if ([string]$existing.Description -ne [string]$desired.Description) {
            $existing.Description = $desired.Description
            $needsUpdate = $true
        }

        if ($needsUpdate) {
            Write-Log "UPDATE: $($desired.Name) -> $($desired.Number)"

            if (-not $WhatIf) {
                Update-IpPbxPhonebookEntry -PhoneBookEntry $existing
            }
        }
    }

    $desiredNames = @($DesiredEntries.Name)

    foreach ($existing in $ExistingEntries) {
        if ($desiredNames -notcontains $existing.Name) {
            Write-Log "REMOVE: $($existing.Name) -> $($existing.Number)"

            if (-not $WhatIf) {
                Remove-IpPbxPhoneBookEntry -PhoneBookEntry $existing -Confirm:$false
            }
        }
    }
}

try {
    Remove-ExpiredLogs
    Assert-RequiredCommands

    Write-Log "=== Sync started ==="

    $desiredEntries = Get-DesiredSwyxEntriesFromExchange
    $existingEntries = Get-ManagedSwyxEntries

    Sync-SwyxPhonebook `
        -DesiredEntries $desiredEntries `
        -ExistingEntries $existingEntries `
        -WhatIf:$WhatIf

    Write-Log "=== Sync completed ==="
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)"
    throw
}
