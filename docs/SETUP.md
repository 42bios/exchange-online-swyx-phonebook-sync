# Setup Guide

## Exchange Online authentication

Create an Entra app registration for Exchange Online app-only access.

Typical setup:

1. Create a new app registration.
2. Upload a certificate.
3. Grant `Exchange.ManageAsApp`.
4. Grant admin consent.
5. Ensure the service principal has the required Exchange permissions in your environment.

Example certificate creation:

```powershell
$cert = New-SelfSignedCertificate `
  -Subject "CN=EXO-Swyx-Sync" `
  -CertStoreLocation "Cert:\LocalMachine\My"
```

Example certificate export:

```powershell
Export-Certificate -Cert $cert -FilePath "C:\Temp\cert.cer"
```

Example Exchange Online connection:

```powershell
Connect-ExchangeOnline `
  -AppId "<APP_ID>" `
  -CertificateThumbprint "<THUMBPRINT>" `
  -Organization "<tenant>.onmicrosoft.com"
```

Basic verification:

```powershell
Get-MailContact
Get-Contact
```

## Swyx requirements

The scheduled task should run under a dedicated Windows user that can connect to Swyx interactively.

Recommended characteristics:

- Windows user exists
- Swyx user exists
- no active Swyx license required
- Swyx administrative permissions assigned
- Windows logon works for Swyx management

Basic verification:

```powershell
Connect-IpPbx
Get-IpPbxPhonebookEntry -GlobalPhoneBook
```

## Script configuration

Main settings in `Sync-ExchangeToSwyx.ps1`:

- `$Marker`
- `$LogBasePath`
- `$LogRetentionDays`
- `$AddDefaultCountryCodeToLocalNumbers`
- `$DefaultCountryCode`

Example:

```powershell
$Marker = "[EXO-SYNC]"
$LogBasePath = "C:\System\Swyxware\Scripts\Logs\SwyxSync.log"
$LogRetentionDays = 2
$AddDefaultCountryCodeToLocalNumbers = $false
$DefaultCountryCode = "39"
```

Example number format:

```text
+390000000001
+490000000001
```

## Task Scheduler

The repository includes an anonymized sample definition in `Exchange-Swyx-Phonebook-Sync.sample.xml`.

Typical setup:

- run whether user is logged on or not
- run with highest privileges
- trigger daily at `06:00`
- optionally repeat every `4 hours`

Action:

```powershell
-ExecutionPolicy Bypass -NoProfile -File "C:\Scripts\Sync-ExchangeToSwyx.ps1"
```

## Troubleshooting

### Unauthorized

Admin consent or Exchange role assignment may be missing.

### Certificate not found

```powershell
Get-ChildItem Cert:\LocalMachine\My
```

### Scheduled task does not run

Verify that the configured service account is correct and can access both Exchange and Swyx requirements.

### No contacts returned

```powershell
Get-MailContact
Get-Contact
```

## Notes

- matching is currently based on `Name`
- mobile numbers are created as separate entries with the suffix `(Mobil)`
- only entries containing the configured marker are modified or removed
- GUID-based matching may be a useful future improvement for larger environments
