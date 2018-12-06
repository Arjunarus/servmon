# The function is taken from https://www.powershellmagazine.com/2013/07/19/querying-performance-counters-from-powershell/
# It returns counter ID by its local name
# Exapmle: Get-PerformanceCounterID "ID process"
function Get-PerformanceCounterID
{
    param
    (
        [Parameter(Mandatory=$true)]
        $Name
    )
 
    if ($script:perfHash -eq $null)
    {
        Write-Progress -Activity 'Retrieving PerfIDs' -Status 'Working'
 
        $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\CurrentLanguage'
        $counters = (Get-ItemProperty -Path $key -Name Counter).Counter
        $script:perfHash = @{}
        $all = $counters.Count
 
        for($i = 0; $i -lt $all; $i+=2)
        {
           Write-Progress -Activity 'Retrieving PerfIDs' -Status 'Working' -PercentComplete ($i*100/$all)
           $script:perfHash.$($counters[$i+1]) = $counters[$i]
        }
    }
 
    $script:perfHash.$Name
}

Get-Counter -ListSet * | # get all counter local names
Select-Object -ExpandProperty counter | # Use only counter fields
Select @{Name="Counter"; Expression={$_.split("\")[2]}}, # Take only counter name from full path
       @{Name="ID"; Expression={Get-PerformanceCounterID $_.split("\")[2]}} -Unique | # Take its ID
Sort Counter # Sorting by counter name for easy reading