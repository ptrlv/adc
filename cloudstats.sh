#!/bin/bash
# statsd host
host=py-heimdallr.lancs.ac.uk
port=8125

# cloudscheduler
cstotal=$(cloud_status -m | grep datacentred | wc -l)
echo "cloud.datacentred.cstotal:$cstotal|g" | nc -w 1 -u -v $host $port
csgridpp=$(cloud_status -m | grep gridpp | wc -l)
echo "cloud.imperial.csgridpp:$csgridpp|g" | nc -w 1 -u -v $host $port

# condor
read total claimed unclaimed <<<$(condor_status -const 'VMType=="gridpp-datacentred"' | awk 'END {print $2,$4,$5}')
if [ ${#total} -eq 0 ]; then total=0; fi
if [ ${#claimed} -eq 0 ]; then claimed=0; fi
if [ ${#unclaimed} -eq 0 ]; then unclaimed=0; fi
echo "cloud.datacentred.condortotal:$total|g" | nc -w 1 -u -v $host $port
echo "cloud.datacentred.condorclaimed:$claimed|g" | nc -w 1 -u -v $host $port
echo "cloud.datacentred.condorunclaimed:$unclaimed|g" | nc -w 1 -u -v $host $port

read total claimed unclaimed <<<$(condor_status -const 'VMType=="gridpp-imperial"' | awk 'END {print $2,$4,$5}')
if [ ${#total} -eq 0 ]; then total=0; fi
if [ ${#claimed} -eq 0 ]; then claimed=0; fi
if [ ${#unclaimed} -eq 0 ]; then unclaimed=0; fi
echo "cloud.imperial.condortotal:$total|g" | nc -w 1 -u -v $host $port
echo "cloud.imperial.condorclaimed:$claimed|g" | nc -w 1 -u -v $host $port
echo "cloud.imperial.condorunclaimed:$unclaimed|g" | nc -w 1 -u -v $host $port

read total claimed unclaimed <<<$(condor_status -const 'VMType=="gridpp-oxford"' | awk 'END {print $2,$4,$5}')
if [ ${#total} -eq 0 ]; then total=0; fi
if [ ${#claimed} -eq 0 ]; then claimed=0; fi
if [ ${#unclaimed} -eq 0 ]; then unclaimed=0; fi
echo "cloud.oxford.condortotal:$total|g" | nc -w 1 -u -v $host $port
echo "cloud.oxford.condorclaimed:$claimed|g" | nc -w 1 -u -v $host $port
echo "cloud.oxford.condorunclaimed:$unclaimed|g" | nc -w 1 -u -v $host $port
