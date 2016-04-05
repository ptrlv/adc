#!/bin/bash

shopt -s nullglob

for f in /var/lib/condor/spool/history.*; do
  bn=$(basename $f)
  p=${bn/history/parsed}
  fullp=/data/plove/$p
  echo $fullp
  if [ -f $fullp ]; then continue; fi
  condor_history -l -file $f > $fullp
done
