#!/bin/bash
#------------------------------------------------------------------------------
# resource_logger.sh
#
# -----------------
# Description:
# -----------------
# This scripts logs the CPU, storage and memory information of many servers.
# This is useful if you need to track resources over time across many servers.
# The script will terminate once the specified time has completed.
#
# Requirements:
# -----------------
# The folder to track for storage should be common across servers with
# differences accounted for by wild cards (for example, /data/server*/folder/).
# Each server must be reachable via ssh passwordless.
#------------------------------------------------------------------------------

# Global Variables
# -----------------
# Set these variables so that it matches your environment
# Note that these variables can be overwritten by script arguments
typeset servers='sm156 sm157 sm158 sm159 sm160' #space seperated list of servers
typeset folder_path="/data/data*/hadoop/local"  # folder to monitor for capacity
typeset sleep_mins=15            # time to sleep between iterations (in minutes)
typeset max_hours=1              # maximum time to monitor (in hours)
typeset log="resource_logger.log" # path to the file where output will be logged

# These are internal variables. Do NOT change
typeset sleep_secs=0
typeset max_secs=0
typeset max_iterations=0
typeset rc=0
typeset precheck_failed=0
typeset csv_format=0
typeset output=''
typeset time=''
typeset csv_file=''
typeset size=''
typeset path=''
typeset lock_file='resource_logger.lock'
typeset pid=''
PIDs=()

#------------------------------------------------------------------------------
# show_syntax()
# Displays the syntax of the script for helping the user know how to run it
#------------------------------------------------------------------------------
function show_syntax() {
  echo "resource_logger.sh"
  echo "Description - Logs CPU, Storage and Memory resources of many servers"
  echo "  "
  echo "Usage - resource_logger.sh [-s server_list | -f folder | -l log_file
                      -t sleep_time_mins | -m max_time_hrs | -c csv_file_path ]"
  echo "        -s :  Specify a space-separated list of servers"
  echo "        -f :  Specify the path to get storage info (wild cards are OK)"
  echo "        -l :  Specify the path to the file used for internal logging"
  echo "        -t :  Specify the number of minutes to sleep between monitoring"
  echo "        -m :  Specify the max number of hours to monitor before exiting"
  echo "        -c :  Specify the path to the .csv file to store the results"
  echo ""
  echo "Example:  resource_logger.sh -s 'sm124 sm125' -f '/data*/logs' -t 1 -m 1"
  echo " monitors servers sm124 and sm125 for cpu, memory, and storage capacity"
  echo " of folder ''/data*/logs' every 1 minute for a maximum of 1 hour"
}

#------------------------------------------------------------------------------
# poll_resources()
# Connects via SSH (passwordless) to get CPU, storage and memory information
# input: $server.  The required server name to connect to
# output:  *temp files (deleted before function exits) and *csv file
#------------------------------------------------------------------------------
function poll_resources() {
  typeset server=$1
  typeset formatted_line=''
  typeset timestamp=$(date +'%d%m%y-%H%M%S')
  typeset csv_time=$(date +'%m/%d/%y %H:%M:%S')
  typeset storage_temp_file="resource_logger.$server.$timestamp.storage.temp"
  typeset cpu_temp_file="resource_logger.$server.$timestamp.cpu.temp"
  typeset memory_temp_file="resource_logger.$server.$timestamp.memory.temp"
  typeset storage_output=''
  typeset cpu_output=''
  typeset memory_output=''

  ssh -o BatchMode=yes -o StrictHostKeyChecking=no $server "du -sm ${folder_path} 2>/dev/null" > $storage_temp_file 2>/dev/null
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no $server "top -bn 1 | head -n 20 2>/dev/null" > $cpu_temp_file 2>/dev/null
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no $server "free 2>/dev/null" > $memory_temp_file 2>/dev/null

  #lock on a file so that only one server logs at a time
  #this is to keep all server related-information lines together
  exec 3>$lock_file  #create handle id 3 to open lockfile
  flock -w 10 -x 3 #lock on handle #3 waiting 10s for lock
  echo "${server} storage resources output:" >> $log
  cat $storage_temp_file >> $log
  echo "${server} cpu resources output:" >> $log
  cat $cpu_temp_file >> $log
  echo "${server} memory resources output:" >> $log
  cat $memory_temp_file >> $log
  exec 3>&-  #release lock #3

  # parse the output into a seperate CSV formatted file if needed
  if [[ ${csv_format} == 1 ]]; then
    found_cpu_info=0
    cpu_pct=''
    mem_total=''
    mem_used=''
    mem_free=''
    mem_shared=''
    mem_cache=''
    mem_avail=''
    folder_size=''
    folder_path=''

    #to parse cpu info read the output line by line until the keyword "%CPU" is found
    #then just the next line's 9th column because output should look like:
    #   PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
    # 20192 polkitd   20   0  616532  12376   4448 R  42.1  0.0 622:25.22 polkitd
    while IFS= read line
    do
      if [[ -n $(echo $line | grep '%CPU') ]]; then
        found_cpu_info=1
        continue
      fi
      if [[ $found_cpu_info == 1 ]]; then
        cpu_pct=$(echo $line | awk '{ print $9 }')
        break
      fi
    done < "${cpu_temp_file}"

    # memory information does not need to be read line by line.
    # it sould be in this format:
    #            total        used        free        shared  buff/cache   available
    # Mem:      131450436     7414812   122295292      129060     1740332   122933220
     mem_total=$(cat $memory_temp_file  | grep 'Mem:' | awk '{ print $2 }')
     mem_used=$(cat $memory_temp_file   | grep 'Mem:' | awk '{ print $3 }')
     mem_free=$(cat $memory_temp_file   | grep 'Mem:' | awk '{ print $4 }')
     mem_shared=$(cat $memory_temp_file | grep 'Mem:' | awk '{ print $5 }')
     mem_cache=$(cat $memory_temp_file  | grep 'Mem:' | awk '{ print $6 }')
     mem_avail=$(cat $memory_temp_file  | grep 'Mem:' | awk '{ print $7 }')

    #store all information inside the loop of the storage output
    #this is because the storage information will have many lines (one per folder path)
    #and each folder path will need to be stored as a seperate entry

    exec 3>$lock_file  #create handle id 3 to open lockfile
    flock -w 10 -x 3 #lock on handle #3 waiting 10s for lock
    while IFS= read line
    do
       folder_size=$(echo $line | awk '{ print $1 }')
       folder_path=$(echo $line | awk '{ print $2 }')
       #store all information
       echo "${csv_time},${server},${folder_size},${folder_path},${cpu_pct},${mem_total},${mem_used},${mem_free},${mem_shared},${mem_cache},${mem_avail}" >> $csv_file
    done < "${storage_temp_file}"
    exec 3>&-  #release lock #3
  fi

  #remove temp files
  if [[ -e $storage_temp_file ]]; then
    rm $storage_temp_file
  fi
  if [[ -e $cpu_temp_file ]]; then
    rm $cpu_temp_file
  fi
  if [[ -e $memory_temp_file ]]; then
    rm $memory_temp_file
  fi
}

#------------------------------------------------------------------------------
# abort_handler()
# Will trap on signal abort to exit cleanly
#------------------------------------------------------------------------------
function abort_handler() {
 typeset num_pids=${#PIDs[*]}

 echo "$(date) - WARNING abort detected. Killing running children..." | tee -a $log
 echo "$(date) - There are $num_pids children to check" >> $log

 for pid in ${PIDs[*]}
 do
   if [[ -n $(ps -efa | grep -w $pid  | grep -v grep ) ]]; then
    echo "$(date) - Killing PID $pid" >> $log
    kill -9 $pid
  else
    echo "$(date) - PID $pid already completed" >> $log
   fi
 done

 #remove the file used for locking
 if [[ -e ${lock_file} ]]; then
   rm ${lock_file}
 fi

 if [[ -n $(ls resource_logger*temp 2>/dev/null) ]]; then
   rm resource_logger*temp
 fi

 echo "$(date) - ERROR - Ended execution due to script abort" >> $log
 exit 1
}

#------------------------------------------------------------------------------
# MAIN
#------------------------------------------------------------------------------

# setup the abort handler
trap 'abort_handler' SIGINT

# Handle arguments
while getopts ":c:s:f:t:m:l:" arg; do
  case $arg in
    c)
      csv_file=$OPTARG
      csv_format=1
    ;;
    s)
       servers=$OPTARG
    ;;
    f)
       folder_path=$OPTARG
    ;;
    t)
       sleep_mins=$OPTARG
    ;;
    m)
       max_hours=$OPTARG
    ;;
    l)
       log=$OPTARG
    ;;
    *)
      echo
      show_syntax
      echo "ERROR - Unknown parameter [$arg]"
      exit 1
      ;;
  esac
done

echo "$(date) Starting execution of resource_logger.sh. Log file is [$log]" | tee -a $log
echo " " #print an empty line for readability

#calculate everything in seconds
sleep_secs=$(echo "scale=0; ${sleep_mins}*60" | bc)
max_secs=$(echo "scale=0; ${max_hours}*60*60" | bc)
max_iterations=$(echo "scale=0; ${max_secs}/${sleep_secs}" | bc)

if (( sleep_secs < 1 )); then
  echo "Warning: Sleeping [$sleep_secs] seconds is too low. Sleep 1 secs instead" | tee -a $log
  sleep_secs=1
fi

if (( max_iterations < 1 )); then
  echo "Warning: Iterations [$max_iterations] is too low. Doing at least 1 iteration" | tee -a $log
  max_iterations=l
fi

echo "Will sleep every [$sleep_secs] seconds ($sleep_mins mins)" | tee -a $log
echo "Will iterate a maximum of [$max_secs] seconds ($max_hours hrs)" | tee -a $log
echo "Will iterate a total of [$max_iterations] times" | tee -a $log
echo "Will monitor folder [$folder_path]" | tee -a $log
echo "Will use server list [$servers]" | tee -a $log
if [[ ${csv_format} == 1 ]]; then
  echo "Will store results in csv file [$csv_file]" | tee -a $log
fi

echo " " #print an empty line to screen for readability

#Pre-check. Make sure everything is OK to start monitoring
for a in ${servers}
do
   ping -c 1 ${a} > /dev/null 2>/dev/null
   rc=$?
   if [[ ${rc} != 0 ]]; then
     echo "ERROR - The server ${a} is not reachable. Please check connection" | tee -a $log
     precheck_failed=1
   else
     ssh -o ConnectTimeout=3 -o BatchMode=yes ${a} "ls" > /dev/null 2>/dev/null
     rc=$?
     if [[ ${rc} != 0 ]]; then
       echo "ERROR - The server ${a} is not communicating via SSH. Please check SSH works passwordless" | tee -a $log
       precheck_failed=1
     else
       ssh -o ConnectTimeout=3 -o BatchMode=yes ${a} "ls ${folder_path}" > /dev/null 2>/dev/null
       rc=$?
       if [[ ${rc} != 0 ]]; then
         echo "ERROR - The server ${a} did not find the folder ${folder_path} . Please check path" | tee -a $log
         precheck_failed=1
       fi
     fi
   fi
done

# Write headers if formatting to csv file for the first time
if [[ ${csv_format} == 1 ]]; then
  if [[ ! -e $csv_file ]]; then
     echo "time,server_node,folder_size(MB),folder_path,top_cpu_usg,mem_total,mem_used,mem_free,mem_shared,mem_cached,mem_avail" >> $csv_file
     rc=$?
     if [[ ${rc} != 0 ]]; then
       echo "ERROR - Could not write csv file [$csv_file] . Please check path" | tee -a $log
       precheck_failed=1
     fi
  fi
fi

# Do not continue if precheck failed
if [[ ${precheck_failed} == 1 ]]; then
  echo "ERROR - Please fix the errors above before continuing" | tee -a $log
  exit 1
fi

#remove the file used for locking
if [[ -e ${lock_file} ]]; then
  rm ${lock_file}
fi

# Loop through iterations
let i=0
while (( i < max_iterations ))
do
  time=$(date)
  PIDs=()
  echo "${time} - Getting folder storage . Iteration $i:" >> $log
  for s in ${servers}
  do
    #get server resource information in parallel as seperate threads
    poll_resources ${s} &
    pid=$!
    PIDs+=("$pid")
  done

  # wait for spawned threads to complete
  wait ${PIDs[*]}
  echo "${time} - Threads completed iteration $i. Sleeping $sleep_secs" >> $log
  let i=i+1
  sleep $sleep_secs
done

#remove the file used for locking
if [[ -e ${lock_file} ]]; then
  rm ${lock_file}
fi

echo "Ended execution" | tee -a $log
