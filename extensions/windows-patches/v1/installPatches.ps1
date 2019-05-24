
# Return codes:
#  0 - success
#  1 - install failure
#  2 - download failure
#  3 - unrecognized patch extension

param(
    [string[]] $URIs
)

$logfile = "C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\1.9.3\InstallPatches.log"

Function Write-Log 
{
   Param ([string]$logstring)
   $stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
   $line = "$Stamp $logstring"
   Add-content $logfile -value $line
}

Function Create-ShutdownScript
{

$file = "C:\Windows\Temp\shutdown.bat"
if (Test-Path $file)
{
  Remove-Item $file
}

New-Item $file -ItemType File -Value "@echo off"

$fileContent = @"

set logfile="C:\Windows\Temp\shutdown.log"

echo > %logfile%
echo "Starting Shutdown" >> %logfile%

shutdown.exe /r /t 0 /f /d 2:17  >> %logfile% 2>&1

echo "End" >> %logfile%
"@

Add-Content $file -value $fileContent

}

function DownloadFile([string] $URI, [string] $fullName)
{
    try {
	Write-Host "Downloading $URI"
        Write-Log "Downloading $URI"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing $URI -OutFile $fullName
    } catch {
        Write-Error $_
	      Write-Log $_
        exit 2
    }
}


$URIs | ForEach-Object {
    Write-Host "Processing $_"
    Write-Log "Processing $_"
    $uri = $_
    $pathOnly = $uri
    if ($pathOnly.Contains("?"))
    {
        $pathOnly = $pathOnly.Split("?")[0]
    }
    $fileName = Split-Path $pathOnly -Leaf
    $ext = [io.path]::GetExtension($fileName)
    $fullName = [io.path]::Combine($env:TEMP, $fileName)
    switch ($ext) {
        ".exe" {
            Start-Process -FilePath bcdedit.exe -ArgumentList "/set {current} testsigning on" -Wait
            DownloadFile -URI $uri -fullName $fullName
            Write-Host "Starting $fullName"
            Write-Log "Starting $fullName"
            $proc = Start-Process -Passthru -FilePath "$fullName" -ArgumentList "/q /norestart"
            Wait-Process -InputObject $proc
            switch ($proc.ExitCode)
            {
                0 {
                    Write-Host "Finished running $fullName"
                    Write-Log "Finished running $fullName"
                }
                3010 {
                    Write-Host "Finished running $fullName. Reboot required to finish patching."
                    Write-Log "Finished running $fullName. Reboot required to finish patching."
                }
                Default {
                    Write-Error "Error running $fullName, exitcode $($proc.ExitCode)"
                    Write-Log "Error running $fullName, exitcode $($proc.ExitCode)"
                    exit 1
                }
            }
        }
        ".msu" {
            DownloadFile -URI $uri -fullName $fullName
            Write-Host "Installing $localPath"
            Write-Log "Installing $localPath"
            $proc = Start-Process -Passthru -FilePath wusa.exe -ArgumentList "$fullName /quiet /norestart"
            Wait-Process -InputObject $proc
            switch ($proc.ExitCode)
            {
                0 {
                    Write-Host "Finished running $fullName"
                    Write-Log "Finished running $fullName"
                }
                3010 {
                    Write-Host "Finished running $fullName. Reboot required to finish patching."
                    Write-Log "Finished running $fullName. Reboot required to finish patching."
                }
                Default {
                    Write-Error "Error running $fullName, exitcode $($proc.ExitCode)"
                    Write-Log "Error running $fullName, exitcode $($proc.ExitCode)"
                    exit 1
                }
            }
        }
        Default {
            Write-Error "This script extension doesn't know how to install $ext files"
            Write-Log "This script extension doesn't know how to install $ext files"
            exit 3
        }
    }
}

# No failures, schedule reboot now

Write-Log "Create Shutdown Script."
Create-ShutdownScript

Write-Log "Scheduling Task."
schtasks /create /TN RebootAfterPatch /RU SYSTEM /TR "c:\Windows\Temp\shutdown.bat" /SC ONCE /ST $(([System.DateTime]::Now + [timespan]::FromMinutes(5)).ToString("HH:mm")) /V1 /Z

Write-Log "Task Scheduled."
Write-Log "Listing scheduled tasks."
Get-ScheduledTask >> $logfile
Write-Log "Exiting"
exit 0
