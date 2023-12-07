#!/bin/bash
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

yecho () {
  echo -e "${YELLOW}WARNING: $1${NC}"
}

gecho () {
  echo -e "${GREEN}$1${NC}"
}

recho () {
  echo -e "${RED}ERROR: $1${NC}"
}

if [[ -z "${VITIS_PATH}" ]]; then
  export XILINX_VITIS="/opt/software/FPGA/Xilinx/Vitis/2022.2"
  export VITIS_PATH=${XILINX_VITIS}
  yecho "VITIS_PATH environment variable not found. Using default ${XILINX_VITIS}"
else
  export XILINX_VITIS="${VITIS_PATH}"
fi

if [[ -z "${XILINX_XRT}" ]]; then
  export XILINX_XRT="/opt/software/FPGA/Xilinx/xrt/xrt_2.14"
  yecho "XILINX_XRT environment variable not found. Using default ${XILINX_XRT}"
fi

if [[ -z "${VIVADO_PATH}" ]]; then
  export XILINX_VIVADO="/opt/software/FPGA/Xilinx/Vivado/2022.2"
  export VIVADO_PATH=${XILINX_VIVADO}
  yecho "VIVADO_PATH environment variable not found. Using default ${XILINX_VIVADO}"
else
  export XILINX_VIVADO="${VIVADO_PATH}"
fi

if [[ -z "${HLS_PATH}" ]]; then
  export HLS_PATH="/opt/software/FPGA/Xilinx/Vitis_HLS/2022.2"
  yecho "HLS_PATH environment variable not found. Using default ${HLS_PATH}"
fi

if [ -f "$XILINX_VITIS/settings64.sh" ];then
  #export XILINX_XRT=/opt/xilinx/xrt
  source $XILINX_VITIS/settings64.sh
  echo "Found Vitis at $XILINX_VITIS"
  # if [ -f "$XILINX_XRT/setup.sh" ];then
  #   # source XRT
  #   source $XILINX_XRT/setup.sh
  #   gecho "Found XRT at $XILINX_XRT"
  # else
  #   recho "XRT not found on $XILINX_XRT, did the installation fail?"
  # fi
  #Manual XRT setup to avoid problems on the cluster
  source $XILINX_XRT/share/completions/xbutil-bash-completion
  source $XILINX_XRT/share/completions/xbmgmt-bash-completion
  export LD_LIBRARY_PATH=$XILINX_XRT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  export PATH=$XILINX_XRT/bin${PATH:+:$PATH}
  export PYTHONPATH=$XILINX_XRT/python${PYTHONPATH:+:$PYTHONPATH}
else
  yecho "Unable to find $XILINX_VITIS/settings64.sh"
  yecho "Functionality dependent on Vitis will not be available."
  yecho "If you need Vitis, ensure VITIS_PATH is set correctly and mounted into the Docker container."
  if [ -f "$XILINX_VIVADO/settings64.sh" ];then
    # source Vivado env.vars
    source $XILINX_VIVADO/settings64.sh
    gecho "Found Vivado at $XILINX_VIVADO"
  else
    yecho "Unable to find $XILINX_VIVADO/settings64.sh"
    yecho "Functionality dependent on Vivado will not be available."
    yecho "If you need Vivado, ensure VIVADO_PATH is set correctly and mounted into the Docker container."
  fi
fi

if [ -f "$HLS_PATH/settings64.sh" ];then
  # source Vitis HLS env.vars
  source $HLS_PATH/settings64.sh
  gecho "Found Vitis HLS at $HLS_PATH"
else
  yecho "Unable to find $HLS_PATH/settings64.sh"
  yecho "Functionality dependent on Vitis HLS will not be available."
  yecho "Please note that FINN needs at least version 2020.2 for Vitis HLS support."
  yecho "If you need Vitis HLS, ensure HLS_PATH is set correctly and mounted into the Docker container."
fi

TMP_FOLDER=/tmp/jupyterhub/${USER}
mkdir -p ${TMP_FOLDER}
cd ${TMP_FOLDER} && git clone -b WorkshopVersionPC2_2023 --single-branch https://github.com/LinusJungemann/finn
cd finn
cp -r /finn/finn/deps .
export FINN_ROOT=$TMP_FOLDER/finn
mkdir -p $TMP_FOLDER/workdir
export FINN_WORKDIR=$TMP_FOLDER/workdir
export FINN_BUILD_DIR=${FINN_WORKDIR}/FINN_TMP
mkdir -p $FINN_BUILD_DIR

echo "$@"
export PYTHONUSERBASE=""
batchspawner-singleuser-old "$@"
