$TASK_DIR = "Tasks"
$TASK_NAME_PREFIX = "NextcloudDriveMapper_"
# The first task file has to be the main entry point for the task
$TASK_FILES = @(
    "MapNextcloudDrive.ps1"
)
$CONFIG_FILE = "NextcloudDriveMapperConfig.ps1"
$DEFAULT_CONFIG_ITEMS = @{
    "NC_DRIVE" = "Enter the drive letter to map here (e.g., 'N:')"
    "NC_URL"   = "Enter the URL of your Nextcloud server here"
    "NC_USER"  = "Enter your Nextcloud username here"
}
$USER_HOME_DIR = [System.Environment]::GetFolderPath('UserProfile')

function Install-WebClient {
    param(
        [int]$SleepTime = 2
    )
    Write-Host "Setting up WebClient service..."
    $webClientService = Get-Service -Name WebClient -ErrorAction SilentlyContinue
    if ($null -eq $webClientService) {
        Write-Host "ERROR: WebClient service not found. Please ensure the WebClient service is installed." -ForegroundColor Red
        exit 1
    }
    if($webClientService.StartType -ne [System.ServiceProcess.ServiceStartMode]::Automatic) {
        Write-Host "WebClient service is not set to start automatically! Setting it to automatic..."
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -Command `"Set-Service -Name WebClient -StartupType Automatic; Start-Service -Name WebClient`""
        if(($LASTEXITCODE -ne 0) -or ($SleepTime -le 0)) {
            Write-Host "ERROR: Failed to set WebClient service to automatic. Please check your permissions." -ForegroundColor Red
            exit 1
        }
        Start-Sleep -Seconds $SleepTime
        Install-WebClient -SleepTime (-1)
    }

    Write-Host "WebClient service setup done." -ForegroundColor Green
}

$Label = Read-Host "Enter a label for the task (e.g., 'MyNextcloud')"
if (-not $Label) {
    Write-Host "ERROR: No label provided. Exiting." -ForegroundColor Red
    exit 1
}

$TaskPath = Join-Path (Join-Path -Path $USER_HOME_DIR -ChildPath $TASK_DIR) ($TASK_NAME_PREFIX + $Label)
Write-Host "Installing Nextcloud Drive Mapper with label '$Label' into '$TaskPath'..."
if (-not (Test-Path -Path $TaskPath)) {
    New-Item -ItemType Directory -Path $TaskPath | Out-Null
}
Write-Host "Task directory created at '$TaskPath'." -ForegroundColor Green

Write-Host "Creating configuration file in '$TaskPath'..."
$ConfigFilePath = Join-Path -Path $TaskPath -ChildPath $CONFIG_FILE
if (Test-Path -Path $ConfigFilePath) {
    Clear-Content -Path $ConfigFilePath
} else {
    New-Item -ItemType File -Path $ConfigFilePath | Out-Null
}
Add-Content -Path $ConfigFilePath -Value "`$NC_DRIVE_NAME = '$Label'"
foreach ($key in $DEFAULT_CONFIG_ITEMS.Keys) {
    $value = Read-Host "$($DEFAULT_CONFIG_ITEMS[$key])"
    if (-not $value) {
        $value = $DEFAULT_CONFIG_ITEMS[$key]
    }
    Add-Content -Path $ConfigFilePath -Value "`$$key = '$value'"
}
# Get and store the user password
$NC_PASS = Read-Host -Prompt "Enter your Nextcloud password (will be stored unencrypted)" -AsSecureString
$NC_PASS = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($NC_PASS))
Add-Content -Path $ConfigFilePath -Value "`$NC_PASS = '$NC_PASS'"
Write-Host "Configuration file created at '$ConfigFilePath'." -ForegroundColor Green

Write-Host "Copying task files to '$TaskPath'..."
foreach ($taskFile in $TASK_FILES) {
    $sourcePath = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath $taskFile
    $destPath = Join-Path -Path $TaskPath -ChildPath $taskFile
    if (Test-Path -Path $destPath) {
        Remove-Item -Path $destPath -Force
    }
    Copy-Item -Path $sourcePath -Destination $destPath
}
Write-Host "Task files copied to '$TaskPath'." -ForegroundColor Green

Write-Host "Installing dependencies..."
Install-WebClient
Write-Host "Dependencies installed successfully." -ForegroundColor Green

Write-Host "Setting up scheduled task on user login..."
$TaskMainScript = Join-Path -Path $TaskPath -ChildPath $TASK_FILES[0]
$TaskMainScript = Join-Path -Path $TaskPath -ChildPath $TASK_FILES[0]
$TaskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TaskMainScript`""
$TaskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$TaskPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
$Task = New-ScheduledTask -Action $TaskAction -Trigger $TaskTrigger -Settings $TaskSettings -Principal $TaskPrincipal
# Save the task object to a temporary file for elevation
$taskFile = [System.IO.Path]::GetTempFileName()
$Task | Export-Clixml -Path $taskFile
# Register the task as admin
Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Import-Clixml -Path '$taskFile' | Register-ScheduledTask -TaskName '$($TASK_NAME_PREFIX + $Label)' -Force -ErrorAction Stop; Remove-Item '$taskFile'`""
Write-Host "Scheduled task created successfully." -ForegroundColor Green

Write-Host "Nextcloud Drive Mapper installed successfully in '$TaskPath'." -ForegroundColor Green