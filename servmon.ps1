param (
    [Int32]$uptime_m = 180,                                # max uptime in minutes
    [Int32]$cpu_usage_p = 50,                              # max CPU usage in percents per one core
    [Int32]$memory_usage_p = 50,                           # max memory usage in percents
    [string[]]$proc_exclude_list = @("explorer"),          # exclude list of processes
    [String[]]$mail_list = @()                             # mail list for alerts
)

# SMTP server settings
$MailFrom = "your mail"
$SMTPServer = "your smtp server"
$SMTPPort = 587 # your smtp port
$MailUser = "" 
$MailPassword = ""

# Workaround for stupid localized counter names
# The function is taken from https://www.powershellmagazine.com/2013/07/19/querying-performance-counters-from-powershell/
# It returns counter local name by its ID
# Exapmle: Get-PerformanceCounterLocalName 3798
Function Get-PerformanceCounterLocalName
{
  param
  (
    [UInt32]$ID,
    $ComputerName = $env:COMPUTERNAME
  )
 
  $code = '[DllImport("pdh.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern UInt32 PdhLookupPerfNameByIndex(string szMachineName, uint dwNameIndex, System.Text.StringBuilder szNameBuffer, ref uint pcchNameBufferSize);'
 
  $Buffer = New-Object System.Text.StringBuilder(1024)
  [UInt32]$BufferSize = $Buffer.Capacity
 
  $t = Add-Type -MemberDefinition $code -PassThru -Name PerfCounter -Namespace Utility
  $rv = $t::PdhLookupPerfNameByIndex($ComputerName, $id, $Buffer, [Ref]$BufferSize)
 
  if ($rv -eq 0)
  {
    $Buffer.ToString().Substring(0, $BufferSize-1)
  }
  else
  {
    Throw 'Get-PerformanceCounterLocalName : Unable to retrieve localized name. Check computer name and performance counter ID.'
  }
}

# Magic local independent counter IDs:
# Obtaned with the help of Get-PerformanceCounterID
# Run GetIds.ps1 to know proper values for your windows version
# see https://www.powershellmagazine.com/2013/07/19/querying-performance-counters-from-powershell/ for details

# Constants with ID                       Counter name in english
#-------------------------------         --------------------------------
$PROCESS_COUNTER_SET_ID = 230             # Procecss
$PROCESS_ID_COUNTER_ID = 784              # ID process
$CPU_USAGE_PERCENTS_COUNTER_ID = 5178     # % Processor Time
$WORKING_SET_COUNTER_ID = 180             # Working Set
$UPTIME_SECONDS_COUNTER_ID = 684          # Elapsed Time

# Full amount of physical memory
$total_physical_memory = Get-CimInstance -class "cim_physicalmemory" | 
    Select-Object -ExpandProperty Capacity | 
    Measure-Object -sum | 
    Select-Object -ExpandProperty Sum

# Change memory treshold unit from percents into bytes
$memory_usage_b = $total_physical_memory * $memory_usage_p / 100

# Change uptime threshold unit from minutes into seconds
$uptime_sec = $uptime_m * 60

# Get local name of "process"
$process_counter_name = Get-PerformanceCounterLocalName $PROCESS_COUNTER_SET_ID

# This function returns processes which are exceed threshold for specified counter
Function Get-ThresholdViolatorProcList
{
    param (
        [UInt32]$counter_id,           # ID of counter to be checked
        [UInt64]$threshold,            # Threshold for this counter 
        [UInt32]$samples_count=1       # The number of samples to average, default is 1.
    )

    $exclude_list = $proc_exclude_list

    # Always exclude this special process names:
    $exclude_list += "idle"
    $exclude_list += "system"
    $exclude_list += "_total"
    $exclude_list += "memory compression"

    $counter_name = Get-PerformanceCounterLocalName $counter_id

    Get-Counter "\$process_counter_name(*)\$counter_name" -SampleInterval 1 -MaxSamples $samples_count -ErrorAction SilentlyContinue | # Get specified counter values
    Select-Object -ExpandProperty CounterSamples | # Take only CounterSamples fields
    Where-Object { $exclude_list -notcontains $_.InstanceName } | # Filter objects by InstanceName not in exclude list
    Group {$_.Path} | # Grouping by path, need for MaxSamples more than 1
    Select-Object @{Name="FullProcName"; Expression={Split-Path $_.Name}}, # Making FullProcName from Path, by throwing out its leaf
        @{Name="CounterValue"; Expression={($_.group.CookedValue | Measure-Object -average).Average}} | # making CounterValue by averaging of grouped Cookedvalue
    Where-Object {$_.CounterValue -gt $threshold} # Take only values exceed threshold specified
}

# This function just  formats process list from previous function into text
Function Format-ViolatorsToText 
{
    param (
        [System.Object[]]$list,    # Process list with FullProcName and CounterValue fields taken from Get-ThresholdViolatorProcList
        [Hashtable]$pids,          # pids hashtable with FullProcName:PID values
        [String]$counter_name,     # Just any readable counter name
        [Uint64]$threshold,        # Threshold value to add in string
        [Double]$coeff,            # Coefficient for converting units. For example, "Working set" counter gives memory in bytes, but MB is more beautyful
        [String]$unit              # String representation for used unit in CounterValue and threshold
    )

    foreach ($item in $list) {
        "Process $($item.FullProcname -replace '.*\((.*)\).*', '$1') PID $($pids[$item.FullProcname]): $($item.CounterValue * $coeff) $unit $counter_name exceeds $threshold $unit!"
    }
}

# Getting processes which are exceeds of each threshold
$cpu_violators = Get-ThresholdViolatorProcList -counter_id $CPU_USAGE_PERCENTS_COUNTER_ID -threshold $cpu_usage_p -samples_count 5
$memory_violators = Get-ThresholdViolatorProcList -counter_id $WORKING_SET_COUNTER_ID -threshold $memory_usage_b
$uptime_violators = Get-ThresholdViolatorProcList -counter_id $UPTIME_SECONDS_COUNTER_ID -threshold $uptime_sec

$pids = @{} # hashtable for storing PIDs
Get-ThresholdViolatorProcList -counter_id $PROCESS_ID_COUNTER_ID -threshold 0 | # Get pids as just "ID process" counter with 0 threshold (all PIDs > 0)
Foreach {$pids[$_.FullProcName] = $_.CounterValue}                              # Converting result into hashtable

# Getting string list for sending on email by converting process lists into text
$stringlist = Format-ViolatorsToText $cpu_violators $pids -counter_name "CPU usage" -threshold $cpu_usage_p -coeff 1 -unit "%"
$stringlist += Format-ViolatorsToText $memory_violators $pids -counter_name "memory usage" -threshold $memory_usage_p -coeff (100/$total_physical_memory) -unit "%"
$stringlist += Format-ViolatorsToText $uptime_violators $pids -counter_name "running time" -threshold $uptime_m -coeff (1/60) -unit "min."

# Convert string list into one string
$body = $stringlist | Out-String

# Sending an emails if body is not empty
if ($body) {
    # Uncomment this and commnent next line to user and password to be asked 
    #$creds = Get-Credential
    $creds = New-Object System.Management.Automation.PSCredential($MailUser, (ConvertTo-SecureString $MailPassword -AsPlainText -Force))
    Send-MailMessage -From $MailFrom -To $mail_list -Subject Alert -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl -Credential $creds -Body $body
}