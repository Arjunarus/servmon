This servmon script is to check running processes for exceeding several thresholds and to send alerts on email list.

There are 3 checking opitons:
- cpu_usage_p: CPU usage in percents
- uptime_m: elapsed time in minutes
- memory_usage_p: memory usage in percents

Also, you can specify an extra options:
- proc_exclude_list: processes which are no need to check 
- mail_list - list of emails for sending warnings

Example of command line is:  
powershell -Command ./servmon.ps1 -uptime_m 180 -cpu_usage_p 50 -memory_usage_p 50 -proc_exclude_list explorer, totalcmd -mail_list mail1@gmail.com, mail2@gmail.com

Also there are hard-coded SMTP server settings to be configured.

**How script works**

Powershell has Get-Counter command which allow to get performance value for almost any parameter you need.
This script just collects three counters:
1) \Process(*)\% Processor Time
2) \Process(*)\Elapsed Time
3) \Process(*)\Working Set

 And it also get PIDs from a special counter "\Process(*)\ID Process" and matches it by the process names with another counters.
 
 There are 2 problems: 
 1) This counter names are localized, so if you execute Get-Counter "\Process(*)\ID Process" on russian (or any non-english) "Windows", as example, it would not work.
 2) "% Processor Time" of the process is quickly changes, and instant value is almost useless.
 
The second problem is solved by using Get-Counter options: -SampleInterval and -MaxSamples. It takes MaxSamples amount of measure with SampleInterval interval. And then I take an average value of it. 

The first problem is more difficult. The workaround is described here: https://www.powershellmagazine.com/2013/07/19/querying-performance-counters-from-powershell/
The main idea is not to use the string name of counters, but to use their IDs wich are taken from registry. 
There are two functions on that page above: 
1) Get-PerformanceCounterLocalName - to get local name of counter by its ID
2) Get-PerformanceCounterID - to get an ID from local name of counter.

So, I just got the set of necessary IDs with the help of Get-PerformanceCounterID and put them inside the script.
One more problem is that this IDs are differs on different windows versions :( 
So you need to change this constants on every windows version:
- $PROCESS_COUNTER_SET_ID - this id is for "Process"
- $PROCESS_ID_COUNTER_ID - this id is for "ID Process"
- $CPU_USAGE_PERCENTS_COUNTER_ID - this id is for "% Processor Time"
- $WORKING_SET_COUNTER_ID - this id is for "Working Set"
- $UPTIME_SECONDS_COUNTER_ID - this id is for "Elapsed Time"

Use GetIds.ps1 script to know proper IDs.
