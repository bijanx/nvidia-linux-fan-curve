#!/bin/bash
#should be run as root

#temperature that should trigger 100% GPU fan utilization
MAX_GPU_TEMP=75

#IDs of GPUs in space seperated string
GPU_IDS="0 1"

#"cool enough" temp. The temperature below which we assign the baseline fan percentage - we don't care about temps below this
BASELINE_GPU_TEMP=35

#the minimum fan utilization percentage to which we assign all temps at or below the baseline gpu temp
BASELINE_FAN_PERCENTAGE=20

#seconds to wait between fan speed updates
REFRESH_RATE=8

echo "GPU fan controller service started."
export DISPLAY=:0
export XAUTHORITY=/var/run/lightdm/root/:0

for gpu_id in $GPU_IDS; do
  nvidia-settings -a [gpu:$GPU_ID]/GPUFanControlState=1 > /dev/null
done

HOSTNAME=$(hostname)
check=$(nvidia-settings -a [fan:$GPU_ID]/GPUTargetFanSpeed=30 | tr -d [[:space:]])

working="Attribute'GPUTargetFanSpeed'($HOSTNAME:0fan:0)assignedvalue30."
if [[ $check != *$working ]]; then
    echo "error on fan speed assignment: $check"
    echo "Should be: $working"
    exit 1
fi
RATE_OF_CHANGE=$(echo "(100-$BASELINE_FAN_PERCENTAGE)/($MAX_GPU_TEMP-$BASELINE_GPU_TEMP)" | bc -l )

timestamp()
{
  date +"%Y-%m-%d %T"
}

while true
do
  for gpu_id in $GPU_IDS; do
    degreesC=$(nvidia-smi -q -d TEMPERATURE -i $gpu_id | grep 'GPU Current Temp' | grep -o '[0-9]*')

    if (( $degreesC < $BASELINE_GPU_TEMP )); then
      fanSpeed=$BASELINE_FAN_PERCENTAGE
    else
      fanSpeed=$(echo "$RATE_OF_CHANGE * ($degreesC - $BASELINE_GPU_TEMP) + $BASELINE_FAN_PERCENTAGE" | bc -l | cut -d. -f1)
    fi

    if [[ $fanSpeed -gt 100 ]]; then
      fanSpeed=100
    fi

    echo "$(timestamp) GPU: $gpu_id | Temp: $degreesC | Fan Speed: $fanSpeed%"

     nvidia-settings -a [fan:$gpu_id]/GPUTargetFanSpeed=$fanSpeed > /dev/null
  done

  sleep $REFRESH_RATE
done
