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
logfile=/var/log/apf/apf.log
shortname=$(hostname -s)
timestamp=$(date +%Y-%m-%dT%H:%M:%S)
logage=$(age "$logfile")

availability=0
if [[ $age -lt 300 ]]; then
    availability=100
elif [[ $age -lt 600 ]]; then
    availability=75
elif [[ $age -lt 1800 ]]; then
    availability=25
fi

cat <<EOF > $tmpfile
<?xml version="1.0" encoding="UTF-8"?>
<serviceupdate xmlns="http://sls.cern.ch/SLS/XML/update">
  <id>PilotFactory_$shortname</id>
  <availability>$availability</availability>
  <webpage>http://apfmon.lancs.ac.uk</webpage>
  <contact>atlas-project-adc-operations-pilot-factory@cern.ch</contact>
  <timestamp>$timestamp</timestamp>
  <data>
    <numericvalue desc="Age of log file in seconds" name="age">$logage</numericvalue>
  </data>
</serviceupdate>
EOF

if ! curl -s -F file=@$tmpfile xsls.cern.ch >/dev/null ; then
  err "Error sending XML to xsls.cern.ch"
  exit 1
fi

rm -f $tmpfile

# check validity
#xmllint --noout --schema http://itmon.web.cern.ch/itmon/files/xsls_schema.xsd $tmpfile
