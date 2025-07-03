Import-Module "$PSScriptRoot\..\modules\HelperFunctions.psm1" -ErrorAction Stop

function Set-Configuration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$configPath,
        [string]$outConfigPath
    )

    $result = Import-Configuration @PSBoundParameters

    $mergedConfig = $result.Config.Clone()
    $result.OutputConfig.GetEnumerator() | ForEach-Object { $mergedConfig[$_.Key] = $_.Value }

    $script:config = $mergedConfig
    $script:outputConfig = $result.OutputConfig
}

function Test-AndGetRequiredKeys {
    param(
        [string[]]$requiredConfigKeys
    )

    if (-not $requiredConfigKeys) {
        return
    }

    $requiredConfigKeys | ForEach-Object {
        if (-not $script:config.$_) {
            $valueBuffer = Read-Host "$_ not found in configuration. Please enter a value or press Enter to abort."
            if (-not $valueBuffer) {
                throw "Missing required configuration key '$_'."
            }
            else {
                $script:config.$_ = $valueBuffer
            }
        }
    }
}

function Set-MissingDefaultValues {
    param(
        [hashtable]$defaultConfig
    )

    if (-not $defaultConfig) {
        return
    }

    $defaultConfig.GetEnumerator() | ForEach-Object {
        $key = $_.Key
        $value = $_.Value
        if (-not $script:config.$key) {
            Write-Verbose "Setting default value '$value' for key '$key'"
            $script:config.$key = $value
        }
    }
}

function Get-StepIndex {
    param(
        $stepIndex,
        [array]$steps
    )

    try {
        $skipToIndex = [int]$stepIndex - 1
    }
    catch {
        $skipToIndex = -1
        $index = 0
        foreach ($step in $steps) {
            if ($stepIndex -in @($step.Title, $step.Command)) {
                $skipToIndex = $index
                break
            }
            $index++
        }

        if ($skipToIndex -lt 0) {
            throw "Step '$stepIndex' not found."
        }
    }

    return $skipToIndex
}

function Get-StepSkipStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$stepIndex,
        [int]$skipToIndex = -1,
        $stepIsBackup,
        $condition
    )

    if ($stepIsBackup -and $script:SkipBackups) {
        return $true
    }

    if ($stepIndex -ge 0 -and $stepIndex -lt $skipToIndex) {
        return $true
    }

    if ($null -eq $condition) {
        return $false
    }

    if ($condition -is [ScriptBlock]) {
        Write-Verbose "Evaluating $($condition.GetType().FullName) condition for step ${stepIndex}:`n$($condition)"
        $condition = & $condition
    }

    if ($condition -is [bool]) {
        return -not $condition
    }

    throw "Condition for step $stepIndex does not return a boolean value. Please check the step definition."
}

function Get-RunOverview {
    param(
        $header,
        [Parameter(Mandatory = $true)]
        [array]$steps,
        [int]$skipToIndex = -1,
        [int]$stopAfterIndex = -1
    )

    $runOverview = @()
    $stepOverview = @()

    $stepOverview += "The following steps will be executed:"
    $skippedStep = $false
    if ($stopAfterIndex -gt -1) {
        $steps = $steps[0..$stopAfterIndex]
    }
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $step = $steps[$i]
        if (Get-StepSkipStatus -stepIndex $i -skipToIndex $skipToIndex -stepIsBackup $step.IsBackup) {
            $skippedStep = $true
        }
        else {
            $currentStepName = if ($step.Title) { $step.Title } else { $step.Path }
            $stepOverview += "  $($i + 1). $currentStepName"
        }
    }
    if ($skippedStep) {
        $stepOverview += "Steps not listed here will be skipped."
    }

    $runOverview += $header
    $runOverview += $stepOverview
    Write-Host ($runOverview -join "`n") -ForegroundColor Magenta
}

function Register-InterruptHandler {
    # FIXME: The handler does not trigger when hitting Ctrl+C
    $null = Register-EngineEvent -SourceIdentifier ConsoleBreak -Action {
        $global:conBreakCount++
        if ($global:conBreakCount -eq 1) {
            $global:shouldStop = $true
            Write-HostTimed "Ctrl+C pressed. The script will stop after the current step is completed.`nPress again to interrupt the step immediately." -ForegroundColor Yellow
        }
        elseif ($global:conBreakCount -eq 2) {
            Write-HostTimed "Ctrl+C pressed again. Interrupting the current step immediately." -ForegroundColor Red
            throw [System.Management.Automation.Remoting.PSRemotingDataStructureException]::new()
        }
        else {
            Write-HostTimed "The script is already stopping. Please wait for the current step to complete or restart this session." -ForegroundColor Red
        }
    }
}

function Unregister-InterruptHandler {
    $null = Unregister-Event -SourceIdentifier ConsoleBreak
}

function New-SqlXeHandler {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        [string]$OutputPath,
        [string]$DatabaseServer = 'localhost',
        [string]$SessionName,
        [string]$scriptPath = 'sql/SqlXeHandler.ps1'
    )

    if (-not [System.IO.Path]::IsPathRooted($scriptPath)) {
        $scriptPath = Join-Path -Path $script:scriptRoot -ChildPath $scriptPath
    }

    try {
        $scriptPath = Get-Item -Path $scriptPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    }
    catch {
        Write-Warning "SQL XE handler script not found at ${scriptPath}."
        return $false
    }

    try {
        . $scriptPath
    }
    catch {
        Write-Warning "Failed to load SQL Extended event handler script ${scriptPath}."
        return $false
    }

    $constructorArgs = @(
        $DatabaseName,
        $OutputPath,
        $DatabaseServer,
        $SessionName
    )

    try {
        $script:sqlXeHandler = New-Object SqlXeHandler -ArgumentList $constructorArgs
        return $true
    }
    catch {
        Write-Warning "Failed to create SQL XE handler object."
        return $false
    }
}

function New-WorkflowEvent {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Run.Start", "Run.End", "Step.Start", "Step.End")]
        [string]$eventType,
        [Parameter(Mandatory = $true)]
        [string]$eventMessage,
        $eventArgParams = @{ }
    )

    [string]$eventLog = 'Application'
    [string]$eventSource = "BC Upgrade Workflow"

    function Get-EventId {
        switch ($eventType) {
            "Run.Start" { 1001 }
            "Run.End" { 1002 }
            "Step.Start" { 2001 }
            "Step.End" { 2002 }
            Default { 0 }
        }
    }

    # FIXME: object type not found in jumphost environment
    if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
        [System.Diagnostics.EventLog]::CreateEventSource($eventSource, $eventLog)
    }

    $eventArgParams += @{
        RunName = $script:runName
        Config  = $script:config
        DryRun  = $script:DryRun
    }

    $formatData = $eventArgParams | ConvertTo-Json

    $eventId = Get-EventId
    $id = New-Object System.Diagnostics.EventInstance($eventId, 1)
    $evtObject = New-Object System.Diagnostics.EventLog
    $evtObject.Log = $eventLog
    $evtObject.Source = $eventSource

    Write-Verbose "Writing '$eventType' event log entry with ID $eventId"
    $evtObject.WriteEvent($id, @($eventType, $eventMessage, $formatData)) | Out-Null
}

function New-StartRunEvent {
    param(
        [string]$SkipToStep,
        [string]$StopAfterStep,
        [bool]$NoExecutionTimesCSV,
        [string]$configPath
    )

    $eventArgParams = @{
        ConfigPath          = $configPath
        NoExecutionTimesCSV = $NoExecutionTimesCSV
        SkipBackups         = $script:SkipBackups
        SkipToStep          = $SkipToStep
        StopAfterStep       = $StopAfterStep
        FoundOutputConfig   = $script:outputConfig.Count -gt 0
    }
    $eventParams = @{
        eventType      = "Run.Start"
        eventMessage   = "Starting run $script:runName"
        eventArgParams = $eventArgParams
    }

    New-WorkflowEvent @eventParams
}

function New-EndRunEvent {
    param(
        [string]$SkipToStep,
        [string]$StopAfterStep,
        [bool]$NoExecutionTimesCSV,
        [string]$configPath,
        [bool]$isSuccess,
        [bool]$stopped,
        [string]$errorMsg
    )
    $eventArgParams = @{
        ConfigPath          = $configPath
        NoExecutionTimesCSV = $NoExecutionTimesCSV
        SkipBackups         = $script:SkipBackups
        SkipToStep          = $SkipToStep
        StopAfterStep       = $StopAfterStep
        Success             = $isSuccess
        ManuallyStopped     = $stopped
        ExecutionTimes      = $script:execTimes
    }
    if ($errorMsg) {
        $eventArgParams["ErrorMessage"] = $errorMsg
    }
    $eventParams = @{
        eventType      = "Run.End"
        eventMessage   = "Completed run $script:runName"
        eventArgParams = $eventArgParams
    }

    New-WorkflowEvent @eventParams
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$step,
        [Parameter(Mandatory = $true)]
        [int]$stepIndex,
        [Parameter(Mandatory = $true)]
        [int]$stepCount
    )

    $command = $step.Command
    $description = $step.Title
    $pipelineVariable = $step.PipelineVariable

    [hashtable]$params = @{ }
    [string]$fullCommand = $null
    $combinedStream = $null
    $outputBuffer = @()
    $verboseBuffer = @()
    $debugBuffer = @()
    $scriptInfoBuffer = @()
    $timeInfoBuffer = $null

    function New-StartStepEvent {
        $eventArgParams = @{
            Index            = $stepIndex
            Description      = $description
            Command          = $fullCommand
            Params           = $params
            OutputKeys       = $step.Output
            PipelineVariable = $pipelineVariable
        }

        $eventParams = @{
            eventType      = "Step.Start"
            eventMessage   = "Starting step $description"
            eventArgParams = $eventArgParams
        }

        New-WorkflowEvent @eventParams
    }

    function New-BufferString {
        # FIXME: Always returns nothing
        param(
            [Parameter(Position = 0)]
            [array]$buffer
        )

        return $buffer | ForEach-Object {
            try {
                $_.MessageData
            }
            catch {
                $_.ToString()
            }
        } | Out-String
    }

    function New-EndStepEvent {
        $eventArgParams = @{
            Index            = $stepIndex
            Description      = $description
            Command          = $fullCommand
            Params           = $params
            OutputKeys       = $step.Output
            PipelineVariable = $pipelineVariable
            Output           = New-BufferString $outputBuffer
            Verbose          = New-BufferString $verboseBuffer
            Debug            = New-BufferString $debugBuffer
            TotalElapsedTime = $stepExecTime
            TaskElapsedTimes = $subExecTimes
        }

        $totalElapsedTime = $stepExecTime.ElapsedTime.ToString("hh\:mm\:ss")
        $eventMessage = "Completed step $description - Elapsed time: $TotalElapsedTime"

        $eventParams = @{
            eventType      = "Step.End"
            eventMessage   = $eventMessage
            eventArgParams = $eventArgParams
        }

        New-WorkflowEvent @eventParams
    }

    function Add-Output {
        param(
            [Parameter(Mandatory = $true)]
            $outputBuffer,
            [Parameter(Mandatory = $true)]
            [hashtable]$step
        )

        $newOutput = $false

        if ($step.Output) {
            $outputKeys = $step.Output
        }
        else {
            $outputKeys = @()
        }

        if ($outputKeys -is [string]) {
            $outputKeys = @($outputKeys)
        }

        if ($outputBuffer -isnot [Object[]]) {
            $outputBuffer = @($outputBuffer)
        }

        $expectCount = $outputKeys.Count
        $actualCount = $outputBuffer.Count

        if ($expectCount -ne $actualCount) {
            Write-Warning "Expected $expectCount output keys, but received $actualCount."
            Write-Debug "Output keys:`n$($outputKeys | Format-List | Out-String)`nOutput values:`n$($outputBuffer | Format-List | Out-String)"
        }

        for ($i = 0; $i -lt $actualCount; $i++) {
            $value = $outputBuffer[$i]
            if ($i -lt $expectCount) {
                $key = $outputKeys[$i]
            }
            else {
                $key = $null
            }
            if ($key) {
                $newOutput = $true
                $script:config.$key = $value
                $script:outputConfig.$key = $value
                Write-Verbose "Set output key '$key' to value '$value'"
            }
            else {
                Write-Verbose "Discarding output value '$value'"
            }
        }

        return $newOutput
    }

    # If the command is a script, get the full path
    if ($command -is [string]) {
        $isScript = $command -like "*.ps1"
        $extension = [System.IO.Path]::GetExtension($command)
        if ($extension) {
            if ([System.IO.Path]::IsPathRooted($command)) {
                $command = $command
            }
            else {
                $command = Join-Path -Path $script:scriptRoot -ChildPath $command
            }
        }

        $readableCmd = $command
    }
    else {
        $isScript = $false
        $readableCmd = "Custom script"
    }

    if (-not $description) {
        $description = "Running $readableCmd"
    }
    # Write step description to console
    Write-HostTimed "($($stepIndex + 1)/$stepCount) $description" -ForegroundColor Cyan

    # Convert step parameters to hashtable
    [hashtable]$params = @{ }
    if ($step.Params) {
        $params = ConvertTo-Hashtable2 -object $step.Params
        $filteredParams = @{ }
        foreach ($param in $params.GetEnumerator() | Where-Object { $_.Value }) {
            $filteredParams[$param.Key] = $param.Value
        }
        $params = $filteredParams
    }

    if ($VerbosePreference -eq "Continue" -and $isScript) {
        $params["Verbose"] = $true
    }

    # Write full command to verbose stream
    $fullCommand = $command.ToString()
    if ($params) {
        $fullCommand = "$fullCommand $(Get-ParameterString $params)"
    }
    if ($pipelineVariable) {
        $fullCommand = "$(Get-ReadableValue $pipelineVariable) | $fullCommand"
    }

    Write-Verbose $fullCommand

    # Set timestamp for start of the step
    $stepStart = Get-Date

    # Raise event for starting the step
    New-StartStepEvent

    # Execute step
    if (-not $DryRun) {
        # FIXME: Verbose stream is not captured
        # FIXME: Information stream is not captured/No execution times from steps found
        # FIXME: Errors from script blocks do not leave a message
        if ($pipelineVariable) {
            $combinedStream = & $command @params 4>&1 -PipelineVariable $pipelineVariable
        }
        else {
            $combinedStream = & $command @params 4>&1
        }
    }
    else {
        Start-Sleep -Milliseconds 200
        Write-ElapsedTime -startTime $stepStart -command $readableCmd -Silent -InformationVariable combinedStream
    }

    # Split captured stream into information, debug and output buffers
    if ($combinedStream) {
        foreach ($object in $combinedStream) {
            switch ($true) {
                ($object -is [System.Management.Automation.InformationRecord]) { $scriptInfoBuffer += $object }
                ($object -is [System.Management.Automation.VerboseRecord]) { $verboseBuffer += $object }
                ($object -is [System.Management.Automation.DebugRecord]) { $debugBuffer += $object }
                default { $outputBuffer += $object }
            }
        }
    }

    # Add step output to configuration
    if ($step.Output -or $outputBuffer) {
        if (Add-Output -outputBuffer $outputBuffer -step $step) {
            Write-Debug "Output configuration:`n$(ConvertTo-Json -InputObject $script:outputConfig -Depth 10)"
            Write-Verbose "Saving output configuration to $script:outConfigPath"
            if (-not $DryRun) {
                $script:outputConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:outConfigPath -NoNewline -Force
            }
        }
    }

    # Get total execution time of the step
    # TODO: Capture step exec time in case of error & skip, add "status" column
    Write-ElapsedTime -startTime $stepStart -command $description -InformationVariable timeInfoBuffer
    $stepExecTime = Get-ExecTimesFromBuffer -buffer $timeInfoBuffer
    $subExecTimes = Get-ExecTimesFromBuffer -buffer $scriptInfoBuffer

    # TODO: Immediately write exec times to file

    # Raise event for ending the step
    New-EndStepEvent

    # Format description of sub-tasks
    $subExecTimes | ForEach-Object {
        $_.Command = "- $($_.Command)"
    }

    # Add execution times of the step to the global table
    $script:execTimes += $stepExecTime
    $script:execTimes += $subExecTimes
}

function Backup-EventLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,
        [string]$scriptPath = "scripts\debug\Backup-EventLog.ps1",
        [string]$LogName = "Application"
    )

    Write-HostTimed "Backing up event log"
    $backupEventLogParams = @{
        OutputFile = $Output
        LogName    = $LogName
    }
    if (-not [System.IO.Path]::IsPathRooted($scriptPath)) {
        $scriptPath = Join-Path $PWD $scriptPath
    }

    try {
        & $scriptPath @backupEventLogParams
    }
    catch {
        Write-Warning "Unable to back up event log: $_"
    }
}

function Get-FinalExecTimeTable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [datetime]$startTime
    )

    Write-ElapsedTime -startTime $startTime -command "Total Runtime" -InformationVariable totalTime
    $script:execTimes = @(Get-ExecTimesFromBuffer -buffer $totalTime) + $script:execTimes

    $formatTimes = $script:execTimes | Where-Object { $_ } | ForEach-Object {
        Write-Debug "ExecTime object $($_.GetType().Name):`n$_"
        try {
            New-Object PSObject -Property @{
                Task        = $_.Command
                ElapsedTime = $_.ElapsedTime.ToString("c")
                StartTime   = $_.StartTime.ToString("HH:mm:ss")
                EndTime     = $_.EndTime.ToString("HH:mm:ss")
            }
        }
        catch {
            Write-Warning "Failed to format execution time for task '$($_.Command)'."
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }

    return $formatTimes | Select-Object Task, ElapsedTime, StartTime, EndTime
}

function Export-ExecTimes {
    param(
        [Parameter(Mandatory = $true)]
        [array]$formatTimes,
        [Parameter(Mandatory = $true)]
        [string]$configPath,
        $execTimesFolder,
        [Parameter(Mandatory = $true)]
        [string]$runName
    )

    if ($DryRun -or $NoExecutionTimesCSV) {
        $formatTimes | Format-Table -AutoSize
    }
    else {
        $configBaseName = [System.IO.Path]::GetFileNameWithoutExtension($configPath)
        $outputFileName = "${runName}_${configBaseName}_$($script:runStart.ToString("yyyyMMdd_HHmmss")).csv"
        if (-not $execTimesFolder) {
            $execTimesFolder = Join-Path -Path (Split-Path -Path $configPath -Parent) -ChildPath "Execution Times"
        }
        New-Item -ItemType Directory -Path $execTimesFolder -Force | Out-Null
        $csvPath = Join-Path $execTimesFolder $outputFileName
        $formatTimes | Export-Csv -Path $csvPath -NoTypeInformation -Force
        Write-HostTimed "Execution times have been exported to $csvPath"
    }
}

function Get-ExecTimesFromBuffer {
    param(
        $buffer
    )

    if (-not $buffer) {
        return @()
    }

    return $buffer | Where-Object {
        $_ -is [System.Management.Automation.InformationRecord] -and
        $_.Tags -contains "ElapsedTime"
    } | ForEach-Object { $_.MessageData }
}

Write-HostTimed "Workflow functions loaded." -ForegroundColor Cyan
