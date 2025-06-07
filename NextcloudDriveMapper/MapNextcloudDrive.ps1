# Configuration
$DEBUG = $false
$LOGFILE = "$env:TEMP\MapNextcloudDrive.log"
$NC_CONFIG_FILE = "NextcloudDriveMapperConfig.ps1"

$BASE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Log {
    param (
        [string]$message
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LOGFILE -Value "$timestamp - $message"
    Write-DebugMsg $message
}

function Write-DebugMsg {
    param (
        [string]$message
    )
    if( $DEBUG ) {
        Write-Host "[DEBUG] $message"
    }
}

function Main {

    # Clear previous log
    Write-Host "Clearing previous log file: $LOGFILE (if exists)"
    if (Test-Path $LOGFILE) { Remove-Item $LOGFILE }
    New-Item -ItemType File -Path $LOGFILE | Out-Null

    # Source config file
    $ConfigFile = Join-Path -Path $BASE_DIR -ChildPath $NC_CONFIG_FILE
    if (-Not (Test-Path $ConfigFile)) {
        Write-Log "ERROR: Credential file '$ConfigFile' does not exist!"
        exit 1
    }

    Write-Log "Loading config from '$ConfigFile'..."
    . $ConfigFile
    if (-Not $NC_USER -or -Not $NC_PASS) {
        Write-Log "Credentials are not set in '$ConfigFile'. Please edit the file to set your Nextcloud credentials."
        exit 1
    }
    if (-Not $NC_DRIVE -or -Not $NC_URL -or -Not $NC_DRIVE_NAME) {
        Write-Log "ERROR: Required variables (NC_DRIVE, NC_URL, NC_DRIVE_NAME) are not set in '$ConfigFile'."
        exit 1
    }
    if($DEBUG){
        Read-Host "Debug mode is ON. Press Enter to continue..."
    }

    # Check if WebClient service is set to start automatically
    Write-Log "Checking WebClient service running..."
    $WebClientService = Get-Service -Name WebClient -ErrorAction SilentlyContinue
    if ($null -eq $WebClientService) {
        Write-Log "ERROR: WebClient service not found. Please ensure the WebClient service is installed."
        exit 1
    }
    if($WebClientService.StartType -ne [System.ServiceProcess.ServiceStartMode]::Automatic) {
        Write-Log "ERROR: WebClient service is not set to start automatically!"
        exit 1
    }
    # Wait for WebClient service to be running
    while ((Get-Service WebClient).Status -ne 'Running') {
        Write-Host "Waiting for WebClient service to start..."
        Start-Sleep -Seconds 2
    }

    Write-Log "Mapping Nextcloud drive from '$NC_URL' to drive '$NC_DRIVE_NAME'($NC_DRIVE) as user '$NC_USER'..."
    Write-Log "Deleting network drive $NC_DRIVE if exists"
    try {
        $delResult = cmd /c "net use $NC_DRIVE /delete /yes" 2>&1
        Add-Content -Path $LOGFILE -Value $delResult
    } catch {
        Write-Log "ERROR: Failed to delete existing network drive $NC_DRIVE. Continuing..."
    }
    Write-Log "Mapping network drive $NC_DRIVE..."
    $mapResult = cmd /c "net use $NC_DRIVE $NC_URL /user:$NC_USER $NC_PASS" 2>&1
    Add-Content -Path $LOGFILE -Value $mapResult

    if ($LASTEXITCODE -ne 0) {
        Write-Log "[ERROR] Failed to map network drive $NC_DRIVE to $NC_URL."
        exit 1
    }

    # Set drive label in registry
    Write-Log "Setting drive label in registry for $NC_DRIVE to '$NC_DRIVE_NAME'..."
    $regPath = "HKCU:\Network\$($NC_DRIVE.TrimEnd(':'))"
    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "_LabelFromReg" -Value $NC_DRIVE_NAME

    Write-Host "Drive $NC_DRIVE successfully mapped."
    
    if($DEBUG) {
        Read-Host "Press Enter to exit..."
    }
    exit 0
}

Main
