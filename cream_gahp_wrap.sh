#!/bin/sh

export LD_LIBRARY_PATH=/usr/lib64/condor
exec /usr/sbin/cream_gahp $1 $2 $3 $4 $5 $6
