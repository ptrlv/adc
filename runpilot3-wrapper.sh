#!/bin/bash
#
# pilot wrapper used at CERN central pilot factories
#
# https://google.github.io/styleguide/shell.xml


VERSION=20171009-rc
#echo VERSION=${VERSION}
#echo 'This version should not be used yet, exiting'
#exit 1

function err() {
  dt=$(date --utc +"%Y-%m-%d %H:%M:%S %Z [wrapper]")
  echo $dt $@ >&2
}

function log() {
  dt=$(date --utc +"%Y-%m-%d %H:%M:%S %Z [wrapper]")
  echo $dt $@
}

function check_python() {
    pybin=$(which python)
    pyver=`$pybin -c "import sys; print '%03d%03d%03d' % sys.version_info[0:3]"`
    # check if native python version > 2.6.0
    if [ $pyver -ge 002006000 ] ; then
      log "Native python version is > 2.6.0 ($pyver)"
      log "Using $pybin for python compatibility"
    else
      log "refactor: this site has native python < 2.6.0"
      err "warning: this site has native python < 2.6.0"
      log "Native python $pybin is old: $pyver"
    
      # Oh dear, we're doomed...
      log "FATAL: Failed to find a compatible python, exiting"
      err "FATAL: Failed to find a compatible python, exiting"
      monfault 1
      exit 1
    fi
}

function check_proxy() {
  voms-proxy-info -all
  if [[ $? -ne 0 ]]; then
    log "FATAL: error running: voms-proxy-info -all"
    err "FATAL: error running: voms-proxy-info -all"
    monfault exiting 1
    exit 1
  fi
}

function check_cvmfs() {
  if [ -d /cvmfs/atlas.cern.ch/repo/sw ]; then
    log "Found atlas cvmfs software repository"
  else
    log "ERROR: /cvmfs/atlas.cern.ch/repo/sw not found"
    log "FATAL: Failed to find atlas cvmfs software repository. This is a bad site, exiting."
    err "FATAL: Failed to find atlas cvmfs software repository. This is a bad site, exiting."
    monfault 1
    exit 1
  fi
}
  
function check_tags() {
  if [ -e /cvmfs/atlas.cern.ch/repo/sw/tags ]; then
    echo "sha256sum /cvmfs/atlas.cern.ch/repo/sw/tags"
    sha256sum /cvmfs/atlas.cern.ch/repo/sw/tags
  else
    log "ERROR: tags file does not exist: /cvmfs/atlas.cern.ch/repo/sw/tags, exiting."
    err "ERROR: tags file does not exist: /cvmfs/atlas.cern.ch/repo/sw/tags, exiting."
    monfault 1
    exit 1
  fi
  echo
}

function setup_alrb() {
  if [ -d /cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase ]; then
    log 'source ${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh'
    export ATLAS_LOCAL_ROOT_BASE='/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase'
    source ${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh
  else
    log "ERROR: ALRB not found: /cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase, exiting"
    err "ERROR: ALRB not found: /cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase, exiting"
    monfault 1
    exit 1
  fi
}

function setup_ddm() {
  if [[ ${PILOT_TYPE} = "RC" ]]; then
    echo "Running: lsetup rucio testing"
    lsetup rucio testing
    if [[ $? -ne 0 ]]; then
      log 'FATAL: error running "lsetup rucio testing", exiting.'
      err 'FATAL: error running "lsetup rucio testing", exiting.'
      monfault 1
      exit 1
    fi
  else
    echo "Running: lsetup rucio"
    lsetup rucio
    if [[ $? -ne 0 ]]; then
      log 'FATAL: error running "lsetup rucio", exiting.'
      err 'FATAL: error running "lsetup rucio", exiting.'
      monfault 1
      exit 1
    fi
  fi

}

# still needed? using VO_ATLAS_SW_DIR is specific to EGI
function setup_local() {
  log "Looking for ${VO_ATLAS_SW_DIR}/local/setup.sh"
  if [[ -f ${VO_ATLAS_SW_DIR}/local/setup.sh ]]; then
    echo "Sourcing ${VO_ATLAS_SW_DIR}/local/setup.sh -s $sflag"
    source ${VO_ATLAS_SW_DIR}/local/setup.sh -s $sflag
  else
    log 'WARNING: No ATLAS local setup found'
    err 'WARNING: this site has no local setup ${VO_ATLAS_SW_DIR}/local/setup.sh'
  fi
}

function setup_davix() {
  log "Sourcing $ATLAS_LOCAL_ROOT_BASE/packageSetups/localSetup.sh davix -q"
  source $ATLAS_LOCAL_ROOT_BASE/packageSetups/localSetup.sh davix -q
  out=$(davix-http --version)
  if [[ $? -eq 0 ]]; then
    log "$out"
  else
    err "davix-http not available, exiting"
    monfault 1
    exit 1
  fi
}

function check_singularity() {
  out=$(singularity --version)
  if [[ $? -eq 0 ]]; then
    log "Singularity binary found, version $out"
  else
    log "Singularity binary not found"
  fi
}

function get_singopts() {
  url="http://pandaserver.cern.ch:25085/cache/schedconfig/$sflag.all.json"
  singopts=$(curl --silent $url | awk -F"'" '/singularity_options/ {print $2}')
  if [[ $? -eq 0 ]]; then
    log "singularity_options found: $singopts"
    echo $singopts
  else
    err "singularity_options not found"
  fi
  
}

function pilot_cmd() {
  if [[ -n "$PILOT_TYPE" ]]; then
    pilot_args="-d $temp $myargs -i $PILOT_TYPE -G 1"
  else
    pilot_args="-d $temp $myargs -G 1"
  fi

  if [[ ${use_singularity} = true ]]; then
    cmd="$singbin exec $singopts /cvmfs/atlas.cern.ch/repo/images/singularity/x86_64-slc6.img python pilot.py $pilot_args"
  else
    cmd="$pybin pilot.py $pilot_args"
  fi
  echo ${cmd}
}

function get_pilot() {
  # N.B. an RC pilot is chosen once every 100 downloads for production and
  # ptest jobs use Paul's development release.

  if [ -v ${PILOT_HTTP_SOURCES} ]; then
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

  for url in ${PILOT_HTTP_SOURCES}; do
    mkdir pilot3
    curl --connect-timeout 30 --max-time 180 -sS $url | tar -C pilot3 -xzf -
    if [ -f pilot3/pilot.py ]; then
      log "Pilot download OK: ${url}"
      return 0
    fi
    log "ERROR: pilot download and extraction failed: ${url}"
    err "ERROR: pilot download and extraction failed: ${url}"
  done
  return 1
}

function monrunning() {
  if [ -z ${APFMON} ]; then
    err "wrapper monitoring not configured"
    return
  fi

  out=$(curl -ksS --connect-timeout 10 --max-time 20 \
             -d state=running -d wrapper=$VERSION \
             ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ $? -eq 0 ]]; then
    log $out
  else
    err "wrapper monitor warning"
    err "ARGS: -d state=exiting -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID}"
  fi
}

function monexiting() {
  if [ -z ${APFMON} ]; then
    err "wrapper monitoring not configured"
    return
  fi

  out=$(curl -ksS --connect-timeout 10 --max-time 20 -d state=exiting -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ $? -eq 0 ]]; then
    log $out
  else
    err "warning: wrapper monitor"
    err "ARGS: -d state=exiting -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID}"
  fi
}

function monfault() {
  if [ -z ${APFMON} ]; then
    err "wrapper monitoring not configured"
    return
  fi

  out=$(curl -ksS --connect-timeout 10 --max-time 20 -d state=fault -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ $? -eq 0 ]]; then
    log $out
  else
    err "warning: wrapper monitor"
    err "ARGS: -d state=fault -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID}"
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
  # Fail early, fail often^H with useful diagnostics
  #
  
  echo "This is ATLAS pilot wrapper version: $VERSION"
  echo "Please send development requests to p.love@lancaster.ac.uk"
  
  log "==== wrapper stdout BEGIN ===="
  err "==== wrapper stderr BEGIN ===="
  # notify monitoring, job running
  monrunning
  echo

  echo "---- Host environment ----"
  echo "hostname:" $(hostname)
  echo "hostname -f:" $(hostname -f)
  echo "pwd:" $(pwd)
  echo "whoami:" $(whoami)
  echo "id:" $(id)
  if [[ -r /proc/version ]]; then
    echo "/proc/version:" $(cat /proc/version)
  fi
  myargs=$@
  echo "cmd: $0 $myargs"
  log "wrapper getopts: -h $hflag -p $pflag -s $sflag -u $uflag -w $wflag"
  echo
  
  # If we have TMPDIR defined, then move into this directory
  # If it's not defined, then stay where we are
  if [ -n "$TMPDIR" ]; then
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
    monfault 1
    exit 1
  fi
    
  log "cd $temp"
  cd $temp
  echo
  
  echo "---- Retrieve pilot code ----"
  get_pilot
  if [[ $? -ne 0 ]]; then
    log "FATAL: failed to retrieve pilot code"
    err "FATAL: failed to retrieve pilot code"
    monfault 1
    exit 1
  fi
  echo
  
  echo "---- JOB Environment ----"
  printenv | sort
  echo
  
  echo "---- Shell process limits ----"
  ulimit -a
  echo
  
  echo "---- Check python version ----"
  check_python
  echo

  echo "---- Proxy Information ----"
  check_proxy
  echo
  
  echo "---- Check cvmfs area ----"
  check_cvmfs
  echo

  echo "---- Check cvmfs freshness ----"
  check_tags
  echo
  
  echo "---- Setup ALRB ----"
  setup_alrb
  echo

  echo "---- Setup DDM ----"
  setup_ddm
  echo

  echo "---- Setup local ATLAS ----"
  setup_local
  echo

  echo "---- Davix setup ----"
  setup_davix
  echo

  echo "---- Check singularity binary ----"
  check_singularity
  echo

  echo "---- Get singularity options ----"
  sing_opts=$(get_singopts)
  echo $sing_opts
  echo

  echo "---- Check whether or not to use singularity ----"
  use_singularity=false  # hardcoded for now
  if [[ ${use_singularity} = true ]]; then
    log 'Will use singularity'
    echo '   _____ _                   __           _ __        '
    echo '  / ___/(_)___  ____ ___  __/ /___ ______(_) /___  __ '
    echo '  \__ \/ / __ \/ __ `/ / / / / __ `/ ___/ / __/ / / / '
    echo ' ___/ / / / / / /_/ / /_/ / / /_/ / /  / / /_/ /_/ /  '
    echo '/____/_/_/ /_/\__, /\__,_/_/\__,_/_/  /_/\__/\__, /   '
    echo '             /____/                         /____/    '
    echo
  else
    log 'Will NOT use singularity'
  fi
  echo

  echo "---- Build pilot cmd ----"
  cmd=$(pilot_cmd)
  echo cmd: ${cmd}
  echo

  echo "---- Ready to run pilot ----"
  trap term_handler SIGTERM
  trap quit_handler SIGQUIT
  trap segv_handler SIGSEGV
  trap xcpu_handler SIGXCPU
  trap usr1_handler SIGUSR1
  trap bus_handler SIGBUS
  cd $temp/pilot3
  log "cd $temp/pilot3"

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
  log "cleanup: rm -rf $temp"
  rm -fr $temp
  
  log "==== wrapper stdout END ===="
  err "==== wrapper stderr END ===="
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
    A) aflag="${OPTARG}" ;;
    v) vflag="${OPTARG}" ;;
    o) oflag="${OPTARG}" ;;
    *) log "Unexpected option ${flag}" ;;
  esac
done

main "$@"
