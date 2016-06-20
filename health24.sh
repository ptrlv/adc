#!/bin/bash
#
# Publish AutoPyFactory service metrics


#docs: http://itmon.web.cern.ch/itmon/recipes/how_to_publish_service_metrics.html
#      http://itmon.web.cern.ch/itmon/recipes/how_to_create_a_service_xml.html

function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

function age() {
  local filename=$1
  local changed=$(stat -c %Y "$filename")
  local now=$(date +%s)
  local elapsed

  let elapsed=now-changed
  echo $elapsed
}

tmpfile=$(mktemp /var/log/autopyfactory/health.XXXXX)

# Test 1
# check apf.log has recently being written to
logfile=/var/log/autopyfactory/autopyfactory.log
shortname=$(hostname -s)
timestamp=$(date +%Y-%m-%dT%H:%M:%S)
apflogage=$(age "$logfile")

status='degraded'
msg='Degraded'
if [[ $apflogage -lt 300 ]]; then
  status='available'
  msg='OK, activity seen in last 5 minutes in apf.log'
elif [[ $apflogage -lt 600 ]]; then
  status='degraded'
  msg='No activity seen for 10 minutes in apf.log'
elif [[ $apflogage -lt 1800 ]]; then
  status='unavailable'
  msg='No activity seen for 30 minutes in apf.log'
fi



# Test 2
# 'condor_q | tail -1' example output:
# 8848 jobs; 10 completed, 0 removed, 1662 idle, 7176 running, 0 held, 0 suspended
summary=$(condor_q | tail -1)

total=$(echo $summary | cut -d' ' -f1)
completed=$(echo $summary | cut -d' ' -f3)
removed=$(echo $summary | cut -d' ' -f5)
idle=$(echo $summary | cut -d' ' -f7)
running=$(echo $summary | cut -d' ' -f9)

#if [[ $completed -gt 5000 ]]; then
#  status='degraded'
#  msg='Number of completed jobs too high (>5000)'
#fi

#if [[ $removed -gt 5000 ]]; then
#  status='degraded'
#  msg='Number of removed jobs too high (>5000)'
#fi

# Test 3
logfile=/var/log/condor/GridmanagerLog.apf
shortname=$(hostname -s)
timestamp=$(date +%Y-%m-%dT%H:%M:%S)
gridage=$(age "$logfile")

#if [[ $gridage -gt 1200 ]]; then
#  status='unavailable'
#  msg='No activity seen for 30 minutes in GridmanagerLog'
#fi

# PAL
status='available'
msg='OK'

cat <<EOF > $tmpfile
<?xml version="1.0" encoding="UTF-8"?>
<serviceupdate xmlns="http://sls.cern.ch/SLS/XML/update">
  <id>PilotFactory_$shortname</id>
  <status>$status</status>
  <webpage>http://apfmon.lancs.ac.uk</webpage>
  <contact>atlas-project-adc-operations-pilot-factory@cern.ch</contact>
  <availabilitydesc>Checks for recent activity in APF and condor logs</availabilitydesc>
  <availabilityinfo>$msg</availabilityinfo>
  <timestamp>$timestamp</timestamp>
  <data>
    <numericvalue desc="Age of autopyfactory.log in seconds" name="apfage">$apflogage</numericvalue>
    <numericvalue desc="Age of GridmanagerLog in seconds" name="gridmanagerage">$gridage</numericvalue>
    <numericvalue desc="Total number of jobs in condor" name="total">$total</numericvalue>
    <numericvalue desc="Number of completed jobs in condor" name="completed">$completed</numericvalue>
    <numericvalue desc="Number of removed jobs in condor" name="removed">$removed</numericvalue>
    <numericvalue desc="Number of idle jobs in condor" name="idle">$idle</numericvalue>
    <numericvalue desc="Number of running jobs in condor" name="running">$running</numericvalue>
  </data>
</serviceupdate>
EOF

#echo $tmpfile
if ! curl -i -s -F file=@$tmpfile xsls.cern.ch >/dev/null ; then
  err "Error sending XML to xsls.cern.ch"
  exit 1
fi

# remove files older than 2880 minutes (48 hours)
find /var/log/autopyfactory/ -type f -name health.* -mmin +1440 -delete

# check validity
#xmllint --noout --schema http://itmon.web.cern.ch/itmon/files/xsls_schema.xsd $tmpfile
