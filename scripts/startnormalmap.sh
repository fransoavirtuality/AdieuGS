#!/bin/bash

cd ../../.. || exit
#SAPIENS_CHECKPOINT_ROOT=/uca/${USER}/sapiens_lite_host

MODE='torchscript' ## original. no optimizations (slow). full precision inference.
# MODE='bfloat16' ## A100 gpus. faster inference at bfloat16

#SAPIENS_CHECKPOINT_ROOT=$SAPIENS_CHECKPOINT_ROOT/$MODE

#----------------------------set your input and output directories----------------------------------------------
#MYROOT='D:/AI/tuts/part2'
MYROOT=$1
MYINPUT=$2
MYOUTPUT=$3
#INPUT=${MYROOT}'/input'
#OUTPUT=${MYROOT}'/output/normals'
INPUT=${MYINPUT}
OUTPUT=${MYOUTPUT}
echo "Input directory set to ${MYINPUT} 
echo "Output directory set to ${MYOUTPUT} 


#--------------------------MODEL CARD---------------
#MODEL_NAME='sapiens_0.3b'; CHECKPOINT='D:/AI/Meta/Sapiens/lite/sapiens_lite_host/torchscript/normal/checkpoints/sapiens_0.3b/sapiens_0.3b_normal_render_people_epoch_66_torchscript.pt2'
#MODEL_NAME='sapiens_0.6b'; CHECKPOINT=D:/AI/Meta/Sapiens/lite/sapiens_lite_host/torchscript/pretrain/checkpoints/sapiens_0.6b/sapiens_0.6b_normal_render_people_epoch_200_$MODE.pt2
#MODEL_NAME='sapiens_1b'; CHECKPOINT=$SAPIENS_CHECKPOINT_ROOT/normal/checkpoints/sapiens_1b/sapiens_1b_normal_render_people_epoch_115_$MODE.pt2
MODEL_NAME='sapiens_2b'; CHECKPOINT=${MYROOT}'/ext/normals/sapiens/lite/normal/checkpoints/sapiens_2b/sapiens_2b_normal_render_people_epoch_70_torchscript.pt2'

#OUTPUT=$OUTPUT/$MODEL_NAME

##-------------------------------------inference-------------------------------------
RUN_FILE=${MYROOT}'/ext/normals/sapiens/lite/demo/normalmap.py'


# JOBS_PER_GPU=1; TOTAL_GPUS=8; VALID_GPU_IDS=(0 1 2 3 4 5 6 7)
JOBS_PER_GPU=1; TOTAL_GPUS=1; VALID_GPU_IDS=(0)

BATCH_SIZE=8

# Find all images and sort them, then write to a temporary text file
IMAGE_LIST="${INPUT}/image_list.txt"
find "${INPUT}" -type f \( -iname \*.jpg -o -iname \*.png \) | sort > "${IMAGE_LIST}"

# Check if image list was created successfully
if [ ! -s "${IMAGE_LIST}" ]; then
  echo "No images found. Check your input directory and permissions."
  exit 1
fi

# Count images and calculate the number of images per text file
NUM_IMAGES=$(wc -l < "${IMAGE_LIST}")
if ((TOTAL_GPUS > NUM_IMAGES / BATCH_SIZE)); then
  TOTAL_JOBS=$(( (NUM_IMAGES + BATCH_SIZE - 1) / BATCH_SIZE))
  IMAGES_PER_FILE=$((BATCH_SIZE))
  EXTRA_IMAGES=$((NUM_IMAGES - ((TOTAL_JOBS - 1) * BATCH_SIZE)  ))
else
  TOTAL_JOBS=$((JOBS_PER_GPU * TOTAL_GPUS))
  IMAGES_PER_FILE=$((NUM_IMAGES / TOTAL_JOBS))
  EXTRA_IMAGES=$((NUM_IMAGES % TOTAL_JOBS))
fi

export TF_CPP_MIN_LOG_LEVEL=2
echo "Distributing ${NUM_IMAGES} image paths into ${TOTAL_JOBS} jobs."

# Divide image paths into text files for each job
for ((i=0; i<TOTAL_JOBS; i++)); do
  TEXT_FILE="${INPUT}/image_paths_$((i+1)).txt"
  if [ $i -eq $((TOTAL_JOBS - 1)) ]; then
    # For the last text file, write all remaining image paths
    tail -n +$((IMAGES_PER_FILE * i + 1)) "${IMAGE_LIST}" > "${TEXT_FILE}"
  else
    # Write the exact number of image paths per text file
    head -n $((IMAGES_PER_FILE * (i + 1))) "${IMAGE_LIST}" | tail -n ${IMAGES_PER_FILE} > "${TEXT_FILE}"
  fi
done

# Run the process on the GPUs, allowing multiple jobs per GPU
for ((i=0; i<TOTAL_JOBS; i++)); do
  GPU_ID=$((i % TOTAL_GPUS))
  CUDA_VISIBLE_DEVICES=${VALID_GPU_IDS[GPU_ID]} 
  python ${RUN_FILE} \
    ${CHECKPOINT} \
    --input "${INPUT}" \
    --seg_dir none \
    --batch-size="${BATCH_SIZE}" \
    --output-root="${OUTPUT}" ## add & to process in background
  # Allow a short delay between starting each job to reduce system load spikes
  sleep 1
done

# Wait for all background processes to finish
wait

# Remove the image list and temporary text files
#rm "${IMAGE_LIST}"
#for ((i=0; i<TOTAL_JOBS; i++)); do
  #rm "${INPUT}/image_paths_$((i+1)).txt"
#done

# Go back to the original script's directory
cd -

echo "Processing complete."
echo "Results saved to $OUTPUT"
