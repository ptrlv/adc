#!/bin/bash
#
# pilot wrapper used at CERN central pilot factories
#

VERSION=20150501

function err() {
  date --utc +"%Y-%m-%d %H:%M:%S %Z [wrapper] $@" >&2
}

function log() {
  date --utc +"%Y-%m-%d %H:%M:%S %Z [wrapper] $@"
}

function lfc_test() {
    echo -n "Testing LFC module for $1: "
    which $1 &> /dev/null
    if [ $? != "0" ]; then
        echo "No $1 found in path."
        return 1
    fi
    $1 <<EOF
import sys
try:
    import lfc
    print "LFC module imported ok."
except:
    print "Failed to import LFC module."
    sys.exit(1)
EOF
}

function find_lfc_compatible_python() {
    ## Try to figure out what python to run

    # We _do_not_ now try to use python from the ATLAS release
    # as at this point we do not know what version of python to
    # use or what architecture. Therefore the strategy now is to
    # use the site environment in which to run the pilot and
    # let the pilot setup the correct ATLAS environment for the
    # job.

    pybin=`which python`
    pyver=`$pybin -c "import sys; print '%03d%03d%03d' % sys.version_info[0:3]"`
    # check if native python version > 2.6.0
    if [ $pyver -ge 002006000 ] ; then
      echo "Native python version is > 2.6.0"
      lfc_test $pybin
      if [ $? = "0" ]; then
        log "refactor: this site has native python $pyver"
        err "refactor: this site has native python $pyver"
        return 0
      else
        echo "Trying cvmfs version..."
      fi
    else
      log "refactor: this site has native python < 2.6.0"
      err "refactor: this site has native python < 2.6.0"
      echo "Native python $pybin is old: $pyver"
      echo "Trying cvmfs version..."
    fi
    
    # try the cvmfs python2.6 binary
    PYTHON26=/cvmfs/atlas.cern.ch/repo/sw/python/latest/setup.sh
    if [ -f $PYTHON26 ] ; then
      if [ ! -z $PYTHONPATH ]; then
        echo "Clobbering PYTHONPATH. Needed to deal with tarball sites when using python2.6"
        unset PYTHONPATH
      fi
      echo "sourcing cvmfs python2.6 setup: $PYTHON26"
      source $PYTHON26
      echo current PYTHONPATH=$PYTHONPATH
      pybin=`which python`
      lfc_test $pybin
      if [ $? = "0" ]; then
        log "refactor: this site using cvmfs python $pybin"
        err "refactor: this site using cvmfs python $pybin"
        return 0
      fi
    else
      echo "cvmfs python2.6 not found"
      err "not found: $PYTHON26"
    fi

    # On many sites python now works just fine (m/w also now
    # distributes the LFC plugin in 64 bit)
    pybin=python
    lfc_test $pybin
    if [ $? = "0" ]; then
        log "refactor: this site using default python $pybin"
        err "refactor: this site using default python $pybin"
        return 0
    fi

    # Now see if python32 exists
    pybin=python32
    lfc_test $pybin
    if [ $? == "0" ]; then
        log "refactor: this site using python32 $pybin"
        err "refactor: this site using python32 $pybin"
        return 0
    fi

    # Oh dear, we're doomed...
    log "ERROR: Failed to find an LFC compatible python, exiting"
    err "ERROR: Failed to find an LFC compatible python, exiting"
    exit 1
}

function get_pilot() {
  # If you define the environment variable PILOT_HTTP_SOURCES then
  # loop over those servers. Otherwise use CERN.
  # N.B. an RC pilot is chosen once every 100 downloads for production and
  # ptest jobs use Paul's development release.

  mkdir pilot3
  cd pilot3

  if [ -z "$PILOT_HTTP_SOURCES" ]; then
    if echo $myargs | grep -- "-u ptest" > /dev/null; then 
      log "This is a ptest pilot. Development pilot will be used"
      PILOT_HTTP_SOURCES="http://project-atlas-gmsb.web.cern.ch/project-atlas-gmsb/pilotcode-dev.tar.gz"
      PILOT_TYPE=PT
    elif [ $(($RANDOM%100)) = "0" ]; then
      log "Release candidate pilot will be used"
      PILOT_HTTP_SOURCES="http://pandaserver.cern.ch:25085/cache/pilot/pilotcode-rc.tar.gz"
      PILOT_TYPE=RC
    else
      log "Normal production pilot will be used" 
      PILOT_HTTP_SOURCES="http://pandaserver.cern.ch:25085/cache/pilot/pilotcode-PICARD.tar.gz"
      PILOT_TYPE=PR
    fi
  fi

  for url in $PILOT_HTTP_SOURCES; do
    curl --connect-timeout 30 --max-time 180 -sS $url | tar -xzf -
    if [ -f pilot.py ]; then
      log "Pilot download OK: $url"
      return 0
    fi
    log "ERROR: pilot download failed: $url"
    err "ERROR: pilot download failed: $url"
  done
  return 1
}

function monrunning() {
  if [ -z ${APFMON:-} ]; then
    err 'wrapper monitoring not configured'
    return
  fi

  out=$(curl -ksS --connect-timeout 10 --max-time 20 \
             -d state=running -d wrapper=$VERSION \
             ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ "$?" -eq 0 ]]; then
    log $out
  else
    err "wrapper monitor warning"
    err "ARGS: -d state=exiting -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID}"
  fi
}

function monexiting() {
  if [ -z ${APFMON:-} ]; then
    err 'wrapper monitoring not configured'
    return
  fi

  out=$(curl -ksS --connect-timeout 10 --max-time 20 -d state=exiting -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ "$?" -eq 0 ]]; then
    log $out
  else
    err "warning: wrapper monitor"
    err "ARGS: -d state=exiting -d rc=$1 -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID}"
  fi
}

function term_handler() {
  log "Caught SIGTERM, sending to pilot PID:$pilotpid"
  err "Caught SIGTERM, sending to pilot PID:$pilotpid"
  kill -s SIGTERM $pilotpid
  wait
}

function quit_handler() {
  log "Caught SIGQUIT, sending to pilot PID:$pilotpid"
  err "Caught SIGQUIT, sending to pilot PID:$pilotpid"
  kill -s SIGQUIT $pilotpid
  wait
}

function segv_handler() {
  log "Caught SIGSEGV, sending to pilot PID:$pilotpid"
  err "Caught SIGSEGV, sending to pilot PID:$pilotpid"
  kill -s SIGSEGV $pilotpid
  wait
}

function xcpu_handler() {
  log "Caught SIGXCPU, sending to pilot PID:$pilotpid"
  err "Caught SIGXCPU, sending to pilot PID:$pilotpid"
  kill -s SIGXCPU $pilotpid
  wait
}

function usr1_handler() {
  log "Caught SIGUSR1, sending to pilot PID:$pilotpid"
  err "Caught SIGUSR1, sending to pilot PID:$pilotpid"
  kill -s SIGUSR1 $pilotpid
  wait
}

function bus_handler() {
  log "Caught SIGBUS, sending to pilot PID:$pilotpid"
  err "Caught SIGBUS, sending to pilot PID:$pilotpid"
  kill -s SIGBUS $pilotpid
  wait
}

function main() {
  #
  # Fail early with useful diagnostics
  #
  # CHANGELOG:
  # refactor and code cleanup
  # added datetime to stdout/err
  # ignore TMPDIR, just run in landing directory
  # removed function set_limits, now done in pilot
  # 
  
  echo "This is ATLAS pilot wrapper version: $VERSION"
  echo "Please send development requests to p.love@lancaster.ac.uk"
  
  log "==== wrapper output BEGIN ===="
  # notify monitoring, job running
  monrunning

  echo "---- Host environment ----"
  echo "hostname:" $(hostname)
  echo "hostname -f:" $(hostname -f)
  echo "pwd:" $(pwd)
  echo "whoami:" $(whoami)
  echo "id:" $(id)
  if [[ -r /proc/version ]]; then
    echo "/proc/version:" $(cat /proc/version)
  fi
  startdir=$(pwd)
  myargs=$@
  echo "cmd: $0 $myargs"
  log "wrapper getopts: -h $hflag -p $pflag -s $sflag -u $uflag -w $wflag"
  echo
  
  # If we have TMPDIR defined, then move into this directory
  # If it's not defined, then stay where we are
  # to be refactored away, always use pwd
  if [ -n "$TMPDIR" ]; then
    err "refactor: this site uses TMPDIR: $TMPDIR"
    err "refactor: this site startdir: $startdir"
    log "cd \$TMPDIR: $TMPDIR"
    cd $TMPDIR
  fi
  templ=$(pwd)/condorg_XXXXXXXX
  temp=$(mktemp -d $templ)
  if [ $? -ne 0 ]; then
    err "Failed: mktemp $templ"
    log "Failed: mktemp $templ"
    err "Exiting."
    log "Exiting."
    exit 1
  fi
    
  log "cd $temp"
  cd $temp
  
  # Try to get pilot code...
  get_pilot
  if [[ "$?" -ne 0 ]]; then
    log "FATAL: failed to retrieve pilot code"
    err "FATAL: failed to retrieve pilot code"
    exit 1
  fi
  
  echo "---- JOB Environment ----"
  printenv | sort
  echo
  
  echo "---- Shell process limits ----"
  ulimit -a
  echo
  
  echo "---- Proxy Information ----"
  voms-proxy-info -all
  echo
  
  # refactor
  # Unset https proxy - this is known to be broken 
  # and is usually unnecessary on the ports used by
  # the panda servers
  unset https_proxy HTTPS_PROXY
  
  # refactor
  # Set LFC api timeouts
  export LFC_CONNTIMEOUT=60
  export LFC_CONRETRY=2
  export LFC_CONRETRYINT=60
  
  # refactor
  # Find the best python to run with
  echo "---- Searching for LFC compatible python ----"
  find_lfc_compatible_python
  echo "Using $pybin for python LFC compatibility"
  echo
  
  # OSG or EGEE?
  # refactor, remove or handle OSG
  echo "---- VO software area ----"
  if [ -n "$VO_ATLAS_SW_DIR" ]; then
    echo "Found EGEE flavour site with software directory $VO_ATLAS_SW_DIR"
    ATLAS_AREA=$VO_ATLAS_SW_DIR
  elif [ -n "$OSG_APP" ]; then
    echo "Found OSG flavor site with software directory $OSG_APP/atlas_app/atlas_rel"
    ATLAS_AREA=$OSG_APP/atlas_app/atlas_rel
  else
    log "ERROR: Failed to find VO_ATLAS_SW_DIR or OSG_APP. This is a bad site, exiting."
    err "ERROR: Failed to find VO_ATLAS_SW_DIR or OSG_APP. This is a bad site, exiting."
    exit 1
    ATLAS_AREA=/bad_site
  fi
  
  ls -l $ATLAS_AREA/
  echo
  if [ -e $ATLAS_AREA/tags ]; then
    echo "sha256sum $ATLAS_AREA/tags"
    sha256sum $ATLAS_AREA/tags
  else
    err "ERROR: tags file does not exist: $ATLAS_AREA/tags, exiting."
    log "ERROR: tags file does not exist: $ATLAS_AREA/tags, exiting."
    exit 1
  fi
  echo
  
  # setup DDM client
  echo "---- DDM setup ----"
  if [ -f /cvmfs/atlas.cern.ch/repo/sw/ddm/latest/setup.sh ]; then
    echo "Sourcing /cvmfs/atlas.cern.ch/repo/sw/ddm/latest/setup.sh"
    source /cvmfs/atlas.cern.ch/repo/sw/ddm/latest/setup.sh
  elif [ -f $ATLAS_AREA/ddm/latest/setup.sh ]; then
    echo "Sourcing $ATLAS_AREA/ddm/latest/setup.sh"
    err "refactor: sourcing $ATLAS_AREA/ddm/latest/setup.sh"
    source $ATLAS_AREA/ddm/latest/setup.sh
  else
    log "WARNING: No DDM setup found to source, exiting."
    err "WARNING: No DDM setup found to source, exiting."
    exit 1
  fi
  echo
  
  echo "---- Local ATLAS setup ----"
  echo "Looking for $ATLAS_AREA/local/setup.sh"
  if [ -f $ATLAS_AREA/local/setup.sh ]; then
      echo "Sourcing $ATLAS_AREA/local/setup.sh -s $sflag"
      source $ATLAS_AREA/local/setup.sh -s $sflag
  else
      log "WARNING: No ATLAS local setup found"
      err "refactor: this site has no local setup $ATLAS_AREA/local/setup.sh"
  fi
  echo

  echo "---- Prepare DDM ToACache ----"
  echo "Looking for $ATLAS_AREA/local/etc/ToACache.py"
  TOACACHE="$ATLAS_AREA/local/etc/ToACache.py"
  TOALCACHE="/var/tmp/.dq2$(whoami)/ToACache.py"
  if [ -s "$TOACACHE" ] ; then
    if [ -L "$TOALCACHE" ] ; then
      log "Link to $TOALCACHE already in place, touching it to extend the vaildity"
      touch -h $TOALCACHE
    else
      log "Linking $TOACACHE to $TOALCACHE"
      rm -f $TOALCACHE && ln -s $TOACACHE $TOALCACHE
    fi
  else
    log "Local $TOACACHE not found (or zero size), continuing"
  fi
  echo
  
  # This is where the pilot rundirectory is - maybe left after job finishes
  scratch=$(pwd)
  
  echo "---- Ready to run pilot ----"
  # If we know the pilot type then set this
  if [ -n "$PILOT_TYPE" ]; then
      pilot_args="-d $scratch $myargs -i $PILOT_TYPE -G 1"
  else
      pilot_args="-d $scratch $myargs -G 1"
  fi
  
  trap term_handler SIGTERM
  trap quit_handler SIGQUIT
  trap segv_handler SIGSEGV
  trap xcpu_handler SIGXCPU
  trap usr1_handler SIGUSR1
  trap bus_handler SIGBUS
  cmd="$pybin pilot.py $pilot_args"
  echo cmd: $cmd
  log "==== pilot stdout BEGIN ===="
  $cmd &
  pilotpid=$!
  wait $pilotpid
  pilotrc=$?
  log "==== pilot stdout END ===="
  log "==== wrapper stdout RESUME ===="
  log "Pilot exit status: $pilotrc"
  
  # notify monitoring, job exiting, capture the pilot exit status
  if [ -f STATUSCODE ]; then
    scode=$(cat STATUSCODE)
  else
    scode=$pilotrc
  fi
  log "STATUSCODE: $scode"
  monexiting $scode
  
  # Now wipe out our temp run directory, so as not to leave rubbish lying around
  cd $startdir
  log "cleanup: rm -rf $temp"
  rm -fr $temp
  
  log "==== wrapper stdout END ===="
  exit
}

hflag=''
pflag=''
sflag=''
uflag=''
wflag=''
while getopts 'h:p:s:u:w:' flag; do
  case "${flag}" in
    h) hflag="${OPTARG}" ;;
    p) pflag="${OPTARG}" ;;
    s) sflag="${OPTARG}" ;;
    u) uflag="${OPTARG}" ;;
    w) wflag="${OPTARG}" ;;
    *) err "Unexpected option ${flag}" ;;
  esac
done

main "$@"
