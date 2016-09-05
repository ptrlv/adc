#!/bin/bash

cmd=/usr/local/bin/agis.py

# only use defined clouds
rm -f /etc/autopyfactory/queues.d/*-analy.conf
rm -f /etc/autopyfactory/queues.d/*-prod.conf
rm -f /etc/autopyfactory/queues.d/ptest.conf

for c in "$@"; do
  if [ "$c" = "ptest" ]; then
    echo /etc/autopyfactory/queues.d/ptest.conf
    $cmd -a ptest > /etc/autopyfactory/queues.d/ptest.conf
  else
    dest=/etc/autopyfactory/queues.d/$c-analy.conf
    echo $dest
    $cmd -c $c -a analysis  > $dest

    dest=/etc/autopyfactory/queues.d/$c-prod.conf
    echo $dest
    $cmd -c $c -a production > $dest
  fi
done
