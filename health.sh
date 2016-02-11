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

tmpfile=$(mktemp)

# check apf.log has recently being written to
logfile=/var/log/apf/apf.log
shortname=$(hostname -s)
timestamp=$(date +%Y-%m-%dT%H:%M:%S)
apflogage=$(age "$logfile")

status='degraded'
msg='All ok'
if [[ $apflogage -lt 300 ]]; then
  status='available'
  msg='No activity seen for 5 minutes in apf.log'
elif [[ $apflogage -lt 600 ]]; then
  status='degraded'
  msg='No activity seen for 10 minutes in apf.log'
elif [[ $apflogage -lt 1800 ]]; then
  status='unavailable'
  msg='No activity seen for 30 minutes in apf.log'
fi


logfile=/var/log/condor/GridmanagerLog.apf
shortname=$(hostname -s)
timestamp=$(date +%Y-%m-%dT%H:%M:%S)
gridage=$(age "$logfile")

if [[ $gridage -lt 600 ]]; then
  status='unavailable'
  msg='No activity seen for 10 minutes in GridmanagerLog'
fi

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
    <numericvalue desc="Age of apf.log in seconds" name="age">$apflogage</numericvalue>
    <numericvalue desc="Age of MasterLog in seconds" name="age">$gridage</numericvalue>
  </data>
</serviceupdate>
EOF

#echo $tmpfile
if ! curl -s -F file=@$tmpfile xsls.cern.ch >/dev/null ; then
  err "Error sending XML to xsls.cern.ch"
  exit 1
fi

rm -f $tmpfile

# check validity
#xmllint --noout --schema http://itmon.web.cern.ch/itmon/files/xsls_schema.xsd $tmpfile
