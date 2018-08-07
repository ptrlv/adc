#!/bin/bash
#
# pilot wrapper used for ad hoc tests
#
# https://google.github.io/styleguide/shell.xml

VERSION=20180323dev5

echo "This is ATLAS pilot wrapper version: $VERSION"
echo "Please send development requests to p.love@lancaster.ac.uk"

function err() {
  dt=$(date --utc +"%Y-%m-%d %H:%M:%S %Z [wrapper]")
  echo $dt $@ >&2
}

function log() {
  dt=$(date --utc +"%Y-%m-%d %H:%M:%S %Z [wrapper]")
  echo $dt $@
}

function get_workdir {
  # If we have TMPDIR defined, then use this directory
  if [[ -n ${TMPDIR} ]]; then
    cd ${TMPDIR}
  fi
  templ=$(pwd)/condorg_XXXXXXXX
  temp=$(mktemp -d $templ)
  echo ${temp}
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
      apfmon_fault 1
      exit 1
    fi
}

function check_proxy() {
  voms-proxy-info -all
  if [[ $? -ne 0 ]]; then
    log "FATAL: error running: voms-proxy-info -all"
    err "FATAL: error running: voms-proxy-info -all"
    apfmon_fault 1
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
    apfmon_fault 1
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
    apfmon_fault 1
    exit 1
  fi
  echo
}

function setup_alrb() {
  if [ -d /cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase ]; then
    log 'source ${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh'
    source ${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh
  else
    log "ERROR: ALRB not found: /cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase, exiting"
    err "ERROR: ALRB not found: /cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase, exiting"
    apfmon_fault 1
    exit 1
  fi
}

function setup_tools() {
  if [[ ${PILOT_TYPE} = "RC" ]]; then
    log 'PILOT_TYPE=RC, lsetup "rucio testing" davix xrootd'
    lsetup "rucio testing" davix xrootd
    if [[ $? -ne 0 ]]; then
      log 'FATAL: error running: lsetup "rucio testing" davix xrootd'
      err 'FATAL: error running: lsetup "rucio testing" davix xrootd'
      apfmon_fault 1
      exit 1
    fi
  else
    log 'lsetup rucio davix xrootd'
    lsetup rucio davix xrootd 
    if [[ $? -ne 0 ]]; then
      log 'FATAL: error running "lsetup rucio davix xrootd", exiting.'
      err 'FATAL: error running "lsetup rucio davix xrootd", exiting.'
      apfmon_fault 1
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
  # OSG MW setup
  if [[ -f ${OSG_GRID}/setup.sh ]]; then
    log "Setting up OSG MW using ${OSG_GRID}/setup.sh"
    source ${OSG_GRID}/setup.sh
  fi
}

function apfmon_running() {
  if [ -z ${APFMON} ]; then
    err "wrapper monitoring not configured"
    return
  fi

  out=$(curl -ksS --connect-timeout 10 --max-time 20 \
             -d state=running -d wrapper=$VERSION \
             ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ $? -eq 0 ]]; then
    log $out
    err $out
  else
    err "wrapper monitor warning"
    err "ARGS: -d state=running -d wrapper=$VERSION ${APFMON}/jobs/${APFFID}:${APFCID}"
  fi
}

function apfmon_exiting() {
  if [ -z ${APFMON} ]; then
    err "wrapper monitoring not configured"
    return
  fi

  out=$(curl -ksS --connect-timeout 10 --max-time 20 \
             -d state=exiting -d rc=$1 -d ids=$2 \
             ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ $? -eq 0 ]]; then
    log $out
  else
    err "WARNING: wrapper monitor"
    err "ARGS: -d state=exiting -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID}"
  fi
}

function apfmon_fault() {
  if [ -z ${APFMON} ]; then
    err "wrapper monitoring not configured"
    return
  fi

  out=$(curl -ksS --connect-timeout 10 --max-time 20 -d state=fault -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ $? -eq 0 ]]; then
    log $out
  else
    err "WARNING: wrapper monitor"
    err "ARGS: -d state=fault -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID}"
  fi
}

function trap_handler() {
  log "Caught $1, signalling pilot PID: $pilotpid"
  kill -s $1 $pilotpid
  wait
}

function main() {
  #
  # Fail early, fail often^W with useful diagnostics
  #

  log "==== wrapper stdout BEGIN ===="
  err "==== wrapper stderr BEGIN ===="
  apfmon_running
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
  log "wrapper call: $0 $myargs"
  echo
  
  echo "---- Enter workdir ----"
  workdir=$(get_workdir)
  log "cd ${workdir}"
  cd ${workdir}
  echo
  
  echo "---- JOB Environment ----"
  export SITE_NAME=${sflag}
  export VO_ATLAS_SW_DIR='/cvmfs/atlas.cern.ch/repo/sw'
  export ALRB_noGridMW=YES
  export ALRB_userMenuFmtSkip=YES
  export ATLAS_LOCAL_ROOT_BASE='/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase'
  printenv | sort
  echo
  
  echo "---- Shell process limits ----"
  ulimit -a
  echo
  
  echo "---- Check python version ----"
  check_python
  echo

  echo "---- Check cvmfs area ----"
  check_cvmfs
  echo

  echo "---- Setup ALRB ----"
  setup_alrb
  echo

  echo "---- Setup tools ----"
  setup_tools
  echo

  echo "---- Setup local ATLAS ----"
  setup_local
  echo

  echo "---- Proxy Information ----"
  check_proxy
  echo
  
  echo "---- Ready to run cmd ----"
  log "==== cmd stdout BEGIN ===="

  git clone https://github.com/ptrlv/stressos.git
  cd stressos
  ls -l 
  source /cvmfs/atlas.cern.ch/repo/sw/external/boto/setup.sh
  python -c "import boto; print boto.__version__" 
  cmd=sleep
  $cmd 5 &
  cmdpid=$!
  wait ${cmdpid}
  cmdrc=$?
  log "==== cmd stdout END ===="
  log "==== wrapper stdout RESUME ===="
  log "cmd exit status: ${cmdrc}"
  apfmon_exiting ${cmdrc}

  log "cleanup: rm -rf $workdir"
  rm -fr $workdir
  
  log "==== wrapper stdout END ===="
  err "==== wrapper stderr END ===="
  exit 0
}

fflag=''
hflag=''
pflag=''
sflag=''
uflag=''
wflag=''
while getopts 'f:h:p:s:u:w:' flag; do
  case "${flag}" in
    s) sflag="${OPTARG}" ;;
    *) log "Unexpected option ${flag}" ;;
  esac
done

main "$@"
