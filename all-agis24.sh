#!/bin/bash

cmd=/usr/local/bin/agis.py

for c in "$@"; do
  dest=/etc/autopyfactory/queues.d/$c-analy.conf
  echo $dest
  $cmd -c $c -a analysis  > $dest

  dest=/etc/autopyfactory/queues.d/$c-prod.conf
  echo $dest
  $cmd -c $c -a production > $dest
done
#echo /etc/autopyfactory/queues.d/ptest.conf
#$cmd -a ptest > /etc/autopyfactory/queues.d/ptest.conf
echo
