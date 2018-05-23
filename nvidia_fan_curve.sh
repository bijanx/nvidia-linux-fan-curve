#!/bin/bash
# seconds to wait between fan speed updates
REFRESH_RATE=3

# temperature that should trigger 100% GPU fan utilization
MAX_GPU_TEMP=70

# "cool enough" temp. The temperature below which we assign the baseline fan percentage - we don't care about temps below this
BASELINE_GPU_TEMP=35

# the minimum fan utilization percentage to which we assign all temps at or below the baseline gpu temp
BASELINE_FAN_PERCENTAGE=20

# IDs of GPUs in space seperated string
GPU_IDS="0 1"

# X config
export DISPLAY=:0
export XAUTHORITY=/run/lightdm/root/:0

# stop execution if a command has an error
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

echo "GPU fan controller service started."

for gpu_id in $GPU_IDS; do
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

# execute fan control loop
while true
do
  # for each GPU
  for gpu_id in $GPU_IDS; do

    # get current degrees
    degreesC=$(nvidia-smi -q -d TEMPERATURE -i $gpu_id | grep 'GPU Current Temp' | grep -o '[0-9]*')

    # if temp is below baseline, fan speed is set to baseline setting
    if (( $degreesC < $BASELINE_GPU_TEMP )); then
      fanSpeed=$BASELINE_FAN_PERCENTAGE
    # if temp is above our max threshold, fan speed is set to 100%
    elif (( $degreesC > $MAX_GPU_TEMP )); then
      fanSpeed=100
    # otherwise set fan speed to a value in proportion to temperature between baseline and max
    else
      fanSpeed=$(echo "$RATE_OF_CHANGE * ($degreesC - $BASELINE_GPU_TEMP) + $BASELINE_FAN_PERCENTAGE" | bc -l | cut -d. -f1)
      if [[ $fanSpeed -gt 100 ]]; then
        fanSpeed=100
      fi
    fi

    echo "gpu: $gpu_id | temp: $degreesC | fan: $fanSpeed"
    nvidia-settings -a [fan:$gpu_id]/GPUTargetFanSpeed=$fanSpeed > /dev/null
  done

  sleep $REFRESH_RATE
done
