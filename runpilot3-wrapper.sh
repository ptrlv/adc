#!/bin/bash
#
# pilot wrapper used at CERN central pilot factories
#

VERSION=20140802
VERSION=devel-1309

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
    
    # firstly try the cvmfs python2.6 binary
    if [ -n "$APF_PYTHON26" ]; then
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
      fi
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
      APF_PYTHON26=1
    elif [ $(($RANDOM%100)) = "0" ]; then
      log "Release candidate pilot will be used"
      PILOT_HTTP_SOURCES="http://pandaserver.cern.ch:25085/cache/pilot/pilotcode-rc.tar.gz"
      PILOT_TYPE=RC
      APF_PYTHON26=1
    else
      log "Normal production pilot will be used" 
      PILOT_HTTP_SOURCES="http://pandaserver.cern.ch:25085/cache/pilot/pilotcode.tar.gz"
      PILOT_TYPE=PR
    fi
  fi

  for url in $PILOT_HTTP_SOURCES; do
    echo "Trying to download pilot from $url ..."
    curl --connect-timeout 30 --max-time 180 -sS $url | tar -xzf -
    if [ -f pilot.py ]; then
      echo "Successfully downloaded pilot from $url"
      return 0
    fi
    echo "Download failed: $url"
  done
  return 1
}

function set_limits() {
    # Set some limits to catch jobs which go crazy from killing nodes
    log "refactor: remove shell limits set_limits()"
    
    # 20GB limit for output size (block = 1K in bash)
    fsizelimit=$((20*1024*1024))
    echo Setting filesize limit to $fsizelimit
    ulimit -f $fsizelimit
    
    # Apply memory limit?
    memLimit=0
    while [ $# -gt 0 ]; do
        if [ $1 == "-k" ]; then
            memLimit=$2
            shift $#
        else
            shift
        fi
    done
    if [ $memLimit == "0" ]; then
        echo No VMEM limit set
    else
        # Convert to kB
        memLimit=$(($memLimit*1000))
        echo Setting VMEM limit to ${memLimit}kB
        ulimit -v $memLimit
    fi
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
    err "wrapper monitor warning"
    err "ARGS: -d state=exiting -d rc=$1 -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID}"
  fi
}

function handler() {
  log "Caught SIGTERM, sending to pilot pid=$pilotpid"
  err "Caught SIGTERM, sending to pilot pid=$pilotpid"
  kill -15 $pilotpid
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
  # removed shell limits, now done in pilot
  # 
  
  echo "This is ATLAS pilot wrapper version: $VERSION"
  echo "Please send development requests to p.love@lancaster.ac.uk"
  echo
  
  log "==== wrapper output BEGIN ===="
  err "This wrapper is currently (August) being refactored, please report problems"
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
  echo
  
  # If we have TMPDIR defined, then move into this directory
  # If it's not defined, then stay where we are
  # to be refactored away, always use pwd
  if [ -n "$TMPDIR" ]; then
    err "refactor: this site uses TMPDIR: $TMPDIR"
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
    
  echo Changing work directory to $temp
  cd $temp
  
  # Try to get pilot code...
  get_pilot
  if [[ "$?" -ne 0 ]]; then
    log "FATAL: failed to retrieve pilot code"
    err "FATAL: failed to retrieve pilot code"
    exit 1
  fi
  
  # Set any limits we need to stop jobs going crazy
  echo
  echo "---- Setting crazy job protection limits ----"
  set_limits
  echo
  
  echo "---- JOB Environment ----"
  printenv | sort
  echo
  
  echo "---- Shell Process Limits ----"
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
    err "ERROR: Tags file does not exist: $ATLAS_AREA/tags, exiting."
    log "ERROR: Tags file does not exist: $ATLAS_AREA/tags, exiting."
    exit 1
  fi
  echo
  
  # setup DDM client
  echo "---- DDM setup ----"
  if [ -n "$APF_PYTHON26" ] && [ -f /cvmfs/atlas.cern.ch/repo/sw/ddm/latest/setup.sh ]; then
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
  echo "$ rucio ping"
  echo $(rucio ping)
  echo
  
  echo "---- Local ATLAS setup ----"
  echo "Looking for $ATLAS_AREA/local/setup.sh"
  if [ -f $ATLAS_AREA/local/setup.sh ]; then
      echo "Sourcing $ATLAS_AREA/local/setup.sh"
      source $ATLAS_AREA/local/setup.sh
  else
      log "WARNING: No ATLAS local setup found"
      err "refactor: this site has no local setup $ATLAS_AREA/local/setup.sh"
  fi
  echo
  
  # This is where the pilot rundirectory is - maybe left after job finishes
  scratch=$(pwd)
  
  echo "---- Ready to run pilot ----"
  # If we know the pilot type then set this
  if [ -n "$PILOT_TYPE" ]; then
      pilot_args="-d $scratch $myargs -i $PILOT_TYPE"
  else
      pilot_args="-d $scratch $myargs"
  fi
  
  trap handler SIGTERM
#  refactor: b/g to handle signals
#  cmd="$pybin pilot.py $pilot_args &"
  cmd="$pybin pilot.py $pilot_args"
  echo cmd: $cmd
  log "==== pilot output BEGIN ===="
  $cmd
  pilotpid=$!
  pexitstatus=$?
#  wait $pilotpid
  log "==== pilot output END ===="
  log "pilotpid=$pilotpid"
  log "==== wrapper output RESUME ===="
  
  log "Pilot exit status was $pexitstatus"
  
  # notify monitoring, job exiting, capture the pilot exit status
  if [ -f STATUSCODE ]; then
  echo
    scode=$(cat STATUSCODE)
  else
    scode=$pexitstatus
  fi
  echo -n STATUSCODE:
  echo $scode
  monexiting $scode
  
  # Now wipe out our temp run directory, so as not to leave rubbish lying around
  echo "Now clearing run directory of all files."
  cd $startdir
  rm -fr $temp
  
  # The end
  log "==== wrapper output END ===="
  exit
}

main "$@"
