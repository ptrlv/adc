#!/bin/bash

shopt -s nullglob

for f in /var/lib/condor/spool/history.*; do
  bn=$(basename $f)
  p=${bn/history/parsed}
  echo /data/plove/$p
  if [ -f $p ]; then continue; fi
  condor_history -l -file $f > $p
done
