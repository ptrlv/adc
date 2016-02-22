#!/bin/bash

# get the latest entries from condor_history,
# N: max number to retrieve 
# t: max number of seconds ago
# Update apfmon with the jobstatus (done/fault)

# JobStatus in job ClassAds
# 
# 0   Unexpanded  U
# 1   Idle    I
# 2   Running R
# 3   Removed X
# 4   Completed   C
# 5   Held    H
# 6   Submission_err  E
# 

factory=`hostname -s`
t=300
N=5000
since=$(date --date="$t seconds ago" +%s)

counter=0
while read -r line ; do
  if echo $line | grep --quiet 'Warning: Bad history file'; then
    continue
  fi
  jobid=$(echo $line | awk '{print $1}')
  jobstate=$(echo $line | awk '{print $2}')
  jid=$factory:$jobid
  if [ "$jobstate" -eq "3" ]; then
    state="fault"
  elif [ "$jobstate" -eq "4" ]; then
    state="done"
  else
    state="$jobstate"
  fi
  curl --silent -d state=$state http://apfmon.lancs.ac.uk/api/jobs/$jid &>/dev/null
  echo $jid $state
  counter=$((counter+1))

done < <(condor_history -file $1 -match $N -const "EnteredCurrentStatus>=$since" \
-format '%4d.' ClusterId \
-format '%-3d ' ProcId \
-format '%d\n' JobStatus)

echo Processed $counter jobs.
