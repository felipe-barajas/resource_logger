# resource_logger
Bash script to log storage, cpu and memory resources across many Linux systems

# Description:

This scripts logs the CPU, storage and memory information of many servers.
This is useful if you need to track resources over time across many servers.
The script will terminate once the specified time has completed.

# Requirements:

The systems to track should be running Linux-compatible operating systems able to run SSH, top, free, and du commands in bash.
**Each server to monitor must be reachable via passwordless SSH**  
To track the usage of a filesystem path, all servers should have this path in common. Any differences should be accounted for by wild cards (for example, */data/server\*/folder/*).

# Syntax
**resource_logger.sh [-s server_list | -f filesystem_path | -l log_file | -t sleep_time_mins | -m max_time_hrs | -c csv_file_path ]**

         -s <server_list>     :  Specify a space-separated list of servers  
         -f <filesystem_path> :  Specify the path to get storage info (wild cards are OK)  
         -l <log_file>        :  Specify the path to the file used for internal logging  
         -t <sleep_time_mins> :  Specify the number of minutes to sleep between monitoring  
         -m <max_time_hrs>    :  Specify the max number of hours to monitor before exiting  
         -c <csv_file_path>   :  Specify the path to the .csv file to store the results in csv format  

# Example
`./resource_logger.sh -s 'sm124 sm125 sm126' -f '/data*/yarn/logs' -t 15 -m 12 -c 1-30-2020_results.csv`  
  
  Monitors servers ***sm124, sm125 and sm126*** for cpu, memory, as well as storage capacity of folder ***/data*/yarn/logs*** every ***15*** minutes 
  for a maximum of ***12*** hours. The results will be collected and grouped into a single file called ***1-30-2020_results.csv***
  
  The output of 1-30-2020.csv will look like:
  
  |time	|server_node	|folder_size(MB)	|folder_path	|top_cpu_usg	|mem_total	|mem_used	|mem_free	|mem_shared	|mem_cached	|mem_avail|
  |-----|-------------|-----------------|-------------|-------------|-----------|---------|---------|-----------|-----------|---------|
  |1/29/2020 17:36	|sm124	|1	|/dataa/yarn/logs	|15	|131450436	|7416064	|122293336	|129064	|1741036	|122932628|

  There will also be a log file (default is name is resource_logger.log) which contains additional debug information as well as the raw SSH output data
  
 
