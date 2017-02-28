#!/bin/bash

# get the latest entries from condor_history and process errors message
# using the grok-err.sh script which publishes summary to apfmon

VERSION=20161025

since=$(date --date="2 hours ago" +%s)

condor_history -file /var/lib/condor/spool/history -const "EnteredCurrentStatus>=$since && JobStatus==3" -af MATCH_APF_QUEUE RemoveReason | /usr/local/bin/grok-err.sh


