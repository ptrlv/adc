#!/bin/bash
#
# ATLAS ADC pilot wrapper (pilot1)
#
#

# https://google.github.io/styleguide/shell.xml

VERSION=20181123a

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
  if [[ "${Fflag}" = "Nordugrid-ATLAS" ]]; then
    echo "."
    return
  fi
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
      sortie 1
    fi
}

function check_proxy() {
  # For Nordugrid skip this check
  if [[ "${Fflag}" = "Nordugrid-ATLAS" ]]; then
    return
  fi
  voms-proxy-info -all
  if [[ $? -ne 0 ]]; then
    log "FATAL: error running: voms-proxy-info -all"
    err "FATAL: error running: voms-proxy-info -all"
    apfmon_fault 1
    sortie 1
  fi
}

function check_cvmfs() {
  export VO_ATLAS_SW_DIR=${VO_ATLAS_SW_DIR:-/cvmfs/atlas.cern.ch/repo/sw}
  if [ -d "${VO_ATLAS_SW_DIR}" ]; then
    log "Found atlas cvmfs software repository"
  else
    log "ERROR: ${VO_ATLAS_SW_DIR} not found"
    log "FATAL: Failed to find atlas cvmfs software repository. This is a bad site, exiting."
    err "FATAL: Failed to find atlas cvmfs software repository. This is a bad site, exiting."
    apfmon_fault 1
    sortie 1
  fi
}
  
function check_tags() {
  if [ -e ${VO_ATLAS_SW_DIR}/tags ]; then
    echo "sha256sum ${VO_ATLAS_SW_DIR}/tags"
    sha256sum ${VO_ATLAS_SW_DIR}/tags
  else
    log "ERROR: tags file does not exist: ${VO_ATLAS_SW_DIR}/tags, exiting."
    err "ERROR: tags file does not exist: ${VO_ATLAS_SW_DIR}/tags, exiting."
    apfmon_fault 1
    sortie 1
  fi
  echo
}


function check_vomsproxyinfo() {
  out=$(voms-proxy-info --version 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    log "Check version: ${out}"
    return 0
  else
    log "voms-proxy-info not found"
    return 1
  fi

}

function check_arcproxy() {
  out=$(arcproxy --version 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    log "Check version: ${out}"
    return 0
  else
    log "arcproxy not found"
    return 1
  fi
}

function setup_alrb() {
  export ATLAS_LOCAL_ROOT_BASE=${ATLAS_LOCAL_ROOT_BASE:-/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase}
  export ALRB_userMenuFmtSkip=YES
  export ALRB_noGridMW=NO
  check_vomsproxyinfo || check_arcproxy && export ALRB_noGridMW=YES

  if [ -d "${ATLAS_LOCAL_ROOT_BASE}" ]; then
    log 'source ${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh --quiet'
    source ${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh --quiet
  else
    log "ERROR: ALRB not found: ${ATLAS_LOCAL_ROOT_BASE}, exiting"
    err "ERROR: ALRB not found: ${ATLAS_LOCAL_ROOT_BASE}, exiting"
    apfmon_fault 1
    sortie 1
  fi
}

function setup_tools() {
  log 'NOTE: rucio,davix,xrootd setup now done in local site setup'
  if [[ ${PILOT_TYPE} = "RC" ]]; then
    log 'PILOT_TYPE=RC, setting ALRB_rucioVersion=testing'
    export ALRB_rucioVersion=testing
  fi
  if [[ ${PILOT_TYPE} = "ALRB" ]]; then
    log 'PILOT_TYPE=ALRB, setting ALRB env vars to testing'
    export ALRB_asetupVersion=testing
    export ALRB_xrootdVersion=testing
    export ALRB_davixVersion=testing
    export ALRB_rucioVersion=testing
  fi
}

function setup_local() {
  export SITE_NAME=${sflag}
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
  if [[ "${Fflag}" = "Nordugrid-ATLAS" ]]; then
    pilot_args="$myargs"
  elif [[ -n "${PILOT_TYPE}" ]]; then
    pilot_args="-d $workdir $myargs -i ${PILOT_TYPE} -G 1"
  else
    pilot_args="-d $workdir $myargs -G 1"
  fi
  if [[ -n ${Cflag} ]]; then
    pilot_args="${pilot_args} -C ${Cflag}"
  fi
  cmd="$pybin pilot.py $pilot_args"
  echo ${cmd}
}

function get_pilot() {
  # N.B. an RC pilot is chosen once every 100 downloads for production and
  # ptest jobs use Paul's development release.

  if [[ -f pilotcode.tar.gz ]]; then
    mkdir pilot
    tar -C pilot -xzf pilotcode.tar.gz
    if [ -f pilot/pilot.py ]; then
      log "Pilot extracted from existing tarball"
      return 0
    fi
    log "ERROR: pilot extraction failed"
    err "ERROR: pilot extraction failed"
    return 1
  fi

  if [ -v ${PILOT_HTTP_SOURCES} ]; then
    if echo $myargs | grep -- "-u ptest" > /dev/null; then 
      log "This is a ptest pilot. Development pilot will be used"
      PILOT_HTTP_SOURCES="http://project-atlas-gmsb.web.cern.ch/project-atlas-gmsb/pilotcode-dev.tar.gz"
      PILOT_TYPE=PT
    elif [ $(($RANDOM%100)) = "0" ] && [ "$uflag" == "" ] && [ "$iflag" == "" ]; then
      log "Release candidate pilot will be used"
      PILOT_HTTP_SOURCES="http://pandaserver.cern.ch:25085/cache/pilot/pilotcode-rc.tar.gz"
      PILOT_TYPE=RC
    elif [ "$iflag" == "RC" ] || [ "$uflag" == "rc_test" ]; then
      log "Release candidate pilot will be used due to wrapper cmdline option"
      PILOT_HTTP_SOURCES="http://pandaserver.cern.ch:25085/cache/pilot/pilotcode-rc.tar.gz"
      PILOT_TYPE=RC
    elif [ "$iflag" == "ALRB" ]; then
      log "ALRB pilot, normal production pilot will be used" 
      PILOT_HTTP_SOURCES="http://pandaserver.cern.ch:25085/cache/pilot/pilotcode-PICARD.tar.gz"
      PILOT_TYPE=ALRB
    else
      log "Normal production pilot will be used" 
      PILOT_HTTP_SOURCES="http://pandaserver.cern.ch:25085/cache/pilot/pilotcode-PICARD.tar.gz"
      PILOT_TYPE=PR
    fi
  fi

  for url in ${PILOT_HTTP_SOURCES}; do
    mkdir pilot
    curl --connect-timeout 30 --max-time 180 -sS $url | tar -C pilot -xzf -
    if [ -f pilot/pilot.py ]; then
      log "Pilot download OK: ${url}"
      return 0
    fi
    log "ERROR: pilot download and extraction failed: ${url}"
    err "ERROR: pilot download and extraction failed: ${url}"
  done
  return 1
}

function apfmon_running() {
  echo "running ${VERSION} ${sflag} ${APFFID}:${APFCID}" > /dev/udp/148.88.67.14/28527
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

function nordugrid_pre_processing() {
  if [ -f output.list ]; then
    echo "Warning: output.list exists, this job may have been restarted"
    rm -f output.list
  fi
  ln -s pilot/RunJob.py .
  ln -s pilot/RunJobEvent.py .
  ln -s pilot/VmPeak.py .
  ln -s pilot/PILOTVERSION .
  ln -s pilot/pilot.py .
  export PYTHONPATH=$PYTHONPATH:`pwd`/pilot
}

function nordugrid_post_processing() {
  if [ -f log_extracts.txt ] ; then
    exitcode=`grep ExitCode log_extracts.txt |awk -F '=' '{print $2}'`
    if [[ "$exitcode" == "" ]] ; then
      log "ERROR: ExitCode not in log_extracts.txt - Unknown"
    fi
    mv logfile.xml  metadata.xml
    if [ -f output.list ] ; then
      # New movers: fix surltobeset with SURL from output.list
      logfile=`cat output.list|awk '{print $2}'|sed -e 's#;[^/]*/#/#' -e 's#:checksumtype=.*$##'`
      sed -i "s#att_value=\".*-surltobeset#att_value=\"$logfile#" metadata.xml
      # If logtoOS was used, fix ddmendpoint_tobeset with CERN-PROD_LOGS
      sed -i "s#<endpoint>.*ddmendpoint_tobeset<#<endpoint>CERN-PROD_LOGS<#" metadata.xml
    fi
  else
    mv metadata-*.xml metadata.xml
  fi

  if [ ! -f metadata.xml ]; then
    err "ERROR: Missing metadata.xml"
    sleep 600
    return 91
  fi

  if [ ! -f panda_node_struct.pickle ]; then
    err "ERROR: Missing panda_node_struct.pickle"
    return 92
  fi

  log "metadata"
  cat metadata.xml
  log "---------"

  mv metadata.xml metadata-surl.xml

  if [ ! -f output.list ]; then
    err "ERROR: Missing output.list"
    return 95
  fi

  log "output list"
  cat output.list

  # do a tarball:
  tar -zcf jobSmallFiles.tgz metadata-surl.xml panda_node_struct.pickle || return 93

  if [ ! -f jobSmallFiles.tgz ] ; then 
    err "ERROR: jobSmallFiles.tgz does not exist"
    return 94
  fi

  return 0
}


function sortie() {
  ec=$1
  if [[ $ec -eq 0 ]]; then
    state=exiting
  else
    state=fault
  fi

  duration=$(( $(date +%s) - ${starttime} ))
  echo "${state} ${duration} ${VERSION} ${sflag} ${APFFID}:${APFCID}" > /dev/udp/148.88.67.14/28527
  exit $ec
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
      sortie 0
    else
      log 'Will NOT use singularity, at least not from the wrapper'
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
  log "wrapper getopts: -h $hflag -p $pflag -s $sflag -u $uflag -w $wflag -f $fflag -C ${Cflag} -i ${iflag}"
  echo
  
  echo "---- Enter workdir ----"
  workdir=$(get_workdir)
  if [[ "$fflag" = "false" && -f pandaJobData.out && ! -f ${workdir}/pandaJobData.out ]]; then
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
    sortie 1
  fi
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
  if [[ "${Fflag}" = "Nordugrid-ATLAS" ]]; then
    nordugrid_pre_processing
  else
    if [[ "${fflag}" = "false" && -f pandaJobData.out ]]; then
      log "Copying job description to pilot dir"
      cp pandaJobData.out pilot/pandaJobData.out
    fi
    cd $workdir/pilot
    log "cd $workdir/pilot"
  fi

  echo "---- JOB Environment ----"
  printenv | sort
  echo

  log "==== pilot stdout BEGIN ===="
  $cmd &
  pilotpid=$!
  wait $pilotpid
  pilotrc=$?
  log "==== pilot stdout END ===="
  log "==== wrapper stdout RESUME ===="
  log "Pilot exit status: $pilotrc"
  
  log "---- Extract pandaIDs ----"
  pandaidfile=${workdir}/pilot/pandaIDs.out 
  if [[ -f ${pandaidfile} ]]; then
    log "pandaIDs file found: ${pandaidfile}"
    pandaids=$(paste -s -d, ${pandaidfile})
    log "pandaIDs: ${pandaids}"
  else
    log "pandaIDs file NOT found: ${pandaidfile}"
    err "pandaIDs file NOT found: ${pandaidfile}"
  fi
  echo

  # notify monitoring, job exiting, capture the pilot exit status
  if [[ -f STATUSCODE ]]; then
    scode=$(cat STATUSCODE)
  else
    scode=$pilotrc
  fi
  log "STATUSCODE: ${scode}"
  apfmon_exiting ${scode} ${pandaids}

  if [[ "${Fflag}" = "Nordugrid-ATLAS" ]]; then
    nordugrid_post_processing
    if [[ $? -ne 0 ]]; then
      sortie $?
    fi
  else
    log "cleanup: rm -rf $workdir"
    rm -fr $workdir
  fi

  if [[ -z ${SINGULARITY_INIT} ]]; then
    log "==== wrapper stdout END ===="
    err "==== wrapper stderr END ===="
  fi
  sortie 0
}

starttime=$(date +%s)
Cflag=''
fflag=''
hflag=''
iflag=''
pflag=''
sflag=''
uflag=''
wflag=''
Fflag=''
while getopts 'C:f:h:i:p:s:u:w:F:' flag; do
  case "${flag}" in
    C) Cflag="${OPTARG}" ;;
    f) fflag="${OPTARG}" ;;
    h) hflag="${OPTARG}" ;;
    i) iflag="${OPTARG}" ;;
    p) pflag="${OPTARG}" ;;
    s) sflag="${OPTARG}" ;;
    u) uflag="${OPTARG}" ;;
    w) wflag="${OPTARG}" ;;
    F) Fflag="${OPTARG}" ;;
    A) aflag="${OPTARG}" ;;
    v) vflag="${OPTARG}" ;;
    o) oflag="${OPTARG}" ;;
    *) log "Unexpected option ${flag}" ;;
  esac
done

url="http://pandaserver.cern.ch:25085/cache/schedconfig/${sflag}.all.json"
fabricmon="http://fabricmon.cern.ch/api"
fabricmon="http://apfmon.lancs.ac.uk/api"
if [ -z ${APFMON} ]; then
  APFMON=${fabricmon}
fi
main "$@"
