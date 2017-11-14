#!/bin/bash

set -e

# should be run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# wait for Xauthority
if [ "$1" != "" ]; then
  sleep $1
fi

# temperature that should trigger 100% GPU fan utilization
MAX_GPU_TEMP=70

# "cool enough" temp. The temperature below which we assign the baseline fan percentage - we don't care about temps below this
BASELINE_GPU_TEMP=35

# the minimum fan utilization percentage to which we assign all temps at or below the baseline gpu temp
BASELINE_FAN_PERCENTAGE=20

# seconds to wait between fan speed updates
REFRESH_RATE=3

# IDs of GPUs in space seperated string in (xorg screen values)
# Screen 0 in xorg has to be the monitor I plug into, but that doesnt always correspond with the nvidia order of gpus
# Future improvement: Would be good to add PCI bus map and not have this script in bash
XORG_SCREEN_IDS="0 1"
GPU_UUIDS=( "GPU-e86893d9-e342-0ab0-3982-ac233348bbc9" "GPU-7a5e7093-024d-1816-b2a7-643dacddef1e")

echo "GPU fan controller service started."

export DISPLAY=:0
export XAUTHORITY=/run/lightdm/root/:0

for gpu_id in $XORG_SCREEN_IDS; do
  nvidia-settings -a [gpu:$gpu_id]/GPUFanControlState=1 > /dev/null
done

# Perform a pre-check
HOSTNAME=$(hostname)
check=$(nvidia-settings -a [fan:0]/GPUTargetFanSpeed=30 | tr -d [[:space:]])

working="Attribute'GPUTargetFanSpeed'($HOSTNAME:0fan:0)assignedvalue30."
if [[ $check != *$working ]]; then
    echo "error on fan speed assignment: $check"
    echo "Should be: $working"
    exit 1
fi

# determine rate multiplier based on fan parameters
RATE_OF_CHANGE=$(echo "(100-$BASELINE_FAN_PERCENTAGE)/($MAX_GPU_TEMP-$BASELINE_GPU_TEMP)" | bc -l )

timestamp()
{
  date +"%Y-%m-%d %T"
}

# Execute fan control loop
while true
do
  for gpu_id in $XORG_SCREEN_IDS; do
    uuid=${GPU_UUIDS[$gpu_id]}
    degreesC=$(nvidia-smi -q -d TEMPERATURE -i ${uuid} | grep 'GPU Current Temp' | grep -o '[0-9]*')

    if (( $degreesC < $BASELINE_GPU_TEMP )); then
      fanSpeed=$BASELINE_FAN_PERCENTAGE
    elif (( $degreesC > $MAX_GPU_TEMP )); then
      fanSpeed=100
    else
      fanSpeed=$(echo "$RATE_OF_CHANGE * ($degreesC - $BASELINE_GPU_TEMP) + $BASELINE_FAN_PERCENTAGE" | bc -l | cut -d. -f1)
      if [[ $fanSpeed -gt 100 ]]; then
        fanSpeed=100
      fi
    fi

    echo "xorg_screen: $gpu_id | uuid: $uuid | temp: $degreesC | fan: $fanSpeed"
    nvidia-settings -a [fan:$gpu_id]/GPUTargetFanSpeed=$fanSpeed > /dev/null
  done

  sleep $REFRESH_RATE
done
