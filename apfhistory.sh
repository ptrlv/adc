#!/bin/bash

# process the get the latest entries from condor_history and process errors message
# using the grok-err.sh script which publishes summary to apfmon

VERSION=20170502

f=$()
condor_history -file $f -af:, GlobalJobId MATCH_APF_QUEUE GridResource JobStatus QDate EnteredCurrentStatus RemoveReason 
