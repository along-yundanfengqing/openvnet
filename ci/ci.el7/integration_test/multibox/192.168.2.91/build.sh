#!/bin/bash

export ENV_ROOTDIR="$(cd "$(dirname $(readlink -f "$0"))/.." && pwd -P)"
export NODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="${NODE_DIR}/tmp_root"

. "${ENV_ROOTDIR}/config.source"
. "${NODE_DIR}/vmspec.conf"
. "${ENV_ROOTDIR}/ind-steps/common.source"

ovn_vnmgr=true
ovn_webapi=true

IND_STEPS=(
    "box"
    "ssh"
    "epel"
    "redis"
    "mysql"
    "lxc"
    "sclo-ruby"
    "nettools"
    "openvswitch"
)

initialize
build "${IND_STEPS[@]}"

(
    start_stage=$install \
               build "openvnet"
)
