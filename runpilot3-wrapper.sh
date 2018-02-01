#!/bin/bash
#
# pilot wrapper used at CERN central pilot factories
#
# https://google.github.io/styleguide/shell.xml

VERSION=20171113

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
}

function check_singularity() {
  out=$(singularity --version 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    log "Singularity binary found, version $out"
  else
    log "Singularity binary not found"
  fi
}

function get_singopts() {
  container_opts=$(curl --silent $url | grep container_options | grep -v null)
  if [[ $? -eq 0 ]]; then
    singopts=$(echo $container_opts | awk -F"\"" '{print $4}')
    log "AGIS container_options found"
    echo ${singopts}
    return 0
  else
    log "AGIS container_options not defined"
    echo ''
    return 0
  fi
}

function check_agis() {
  result=$(curl --silent $url | grep container_type | grep 'singularity:wrapper')
  if [[ $? -eq 0 ]]; then
    log "AGIS container_type: singularity:wrapper found"
    return 0
  else
    log "AGIS container_type does not contain singularity:wrapper"
    return 1
  fi
}

function pilot_cmd() {
  if [[ -n "${PILOT_TYPE}" ]]; then
    pilot_args="-d $workdir $myargs -i ${PILOT_TYPE} -G 1"
  else
    pilot_args="-d $workdir $myargs -G 1"
  fi
  cmd="$pybin pilot.py $pilot_args"
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
  else
    err "wrapper monitor warning"
    err "ARGS: -d state=exiting -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID}"
  fi
}

function apfmon_exiting() {
  if [ -z ${APFMON} ]; then
    err "wrapper monitoring not configured"
    return
  fi

  out=$(curl -ksS --connect-timeout 10 --max-time 20 -d state=exiting -d rc=$1 ${APFMON}/jobs/${APFFID}:${APFCID})
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

  if [[ -z ${SINGULARITY_INIT} ]]; then
    log "==== wrapper stdout BEGIN ===="
    err "==== wrapper stderr BEGIN ===="
    apfmon_running
    echo

    echo "---- Check singularity details ----"
    sing_opts=$(get_singopts)
    echo $sing_opts

    check_agis
    if [[ $? -eq 0 ]]; then
      use_singularity=true
    else
      use_singularity=false
    fi

    if [[ ${use_singularity} = true ]]; then
      log 'SINGULARITY_INIT is not set'
      check_singularity
      export ALRB_noGridMW=NO
      export SINGULARITYENV_PATH=${PATH}
      export SINGULARITYENV_LD_LIBRARY_PATH=${LD_LIBRARY_PATH}
      echo '   _____ _                   __           _ __        '
      echo '  / ___/(_)___  ____ ___  __/ /___ ______(_) /___  __ '
      echo '  \__ \/ / __ \/ __ `/ / / / / __ `/ ___/ / __/ / / / '
      echo ' ___/ / / / / / /_/ / /_/ / / /_/ / /  / / /_/ /_/ /  '
      echo '/____/_/_/ /_/\__, /\__,_/_/\__,_/_/  /_/\__/\__, /   '
      echo '             /____/                         /____/    '
      echo
      cmd="singularity exec $sing_opts /cvmfs/atlas.cern.ch/repo/images/singularity/x86_64-slc6.img $0 $@"
      echo "cmd: $cmd"
      log '==== singularity stdout BEGIN ===='
      err '==== singularity stderr BEGIN ===='
      $cmd &
      singpid=$!
      wait $singpid
      log "singularity return code: $?"
      log '==== singularity stdout END ===='
      err '==== singularity stderr END ===='
      log "==== wrapper stdout END ===="
      err "==== wrapper stderr END ===="
      exit 0
    else
      log 'Will NOT use singularity'
    fi
    echo
  else
    log 'SINGULARITY_INIT is set, run basic setup'
    export ALRB_noGridMW=NO
  fi
  
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
  echo "wrapper call: $0 $myargs"
  log "wrapper getopts: -h $hflag -p $pflag -s $sflag -u $uflag -w $wflag -f $fflag"
  echo
  
  echo "---- Enter workdir ----"
  workdir=$(get_workdir)
  if [ "$fflag" = "false" -a -f pandaJobData.out ]; then
    log "Copying job description to working dir"
    cp pandaJobData.out $workdir/pandaJobData.out
  fi
  log "cd ${workdir}"
  cd ${workdir}
  echo
  
  echo "---- Retrieve pilot code ----"
  get_pilot
  if [[ $? -ne 0 ]]; then
    log "FATAL: failed to retrieve pilot code"
    err "FATAL: failed to retrieve pilot code"
    apfmon_fault 1
    exit 1
  fi
  echo
  
  echo "---- JOB Environment ----"
  export SITE_NAME=${sflag}
  export VO_ATLAS_SW_DIR='/cvmfs/atlas.cern.ch/repo/sw'
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
  
  echo "---- Build pilot cmd ----"
  cmd=$(pilot_cmd)
  echo cmd: ${cmd}
  echo

  echo "---- Ready to run pilot ----"
  trap trap_handler SIGTERM SIGQUIT SIGSEGV SIGXCPU SIGUSR1 SIGBUS
  if [ "$fflag" = "false" -a -f pandaJobData.out ]; then
    log "Copying job description to pilot dir"
    cp pandaJobData.out pilot3/pandaJobData.out
  fi
  cd $workdir/pilot3
  log "cd $workdir/pilot3"

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
  apfmon_exiting $scode
  
  log "cleanup: rm -rf $workdir"
  rm -fr $workdir
  
  if [[ -z ${SINGULARITY_INIT} ]]; then
    log "==== wrapper stdout END ===="
    err "==== wrapper stderr END ===="
  fi
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
    f) fflag="${OPTARG}" ;;
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

url="http://pandaserver.cern.ch:25085/cache/schedconfig/$sflag.all.json"
main "$@"
