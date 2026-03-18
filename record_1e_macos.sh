#!/usr/bin/env bash
set -euo pipefail

RESUME_FLAG=""

for arg in "$@"; do
  case "$arg" in
    --resume)
      RESUME_FLAG="--resume=true"
      ;;
    *)
      echo "Unknown arguments: $arg" >&2
      echo "Usage: $0 [--resume]" >&2
      exit 1
      ;;
  esac
done

read FRONT_INDEX WRIST_INDEX < <(
python - "$FRONT_UID" "$WRIST_UID" <<'PY'
import sys
import cv2
from cv2_enumerate_cameras import enumerate_cameras

front_uid = sys.argv[1]
wrist_uid = sys.argv[2]

front_idx = None
wrist_idx = None

for cam in enumerate_cameras(cv2.CAP_AVFOUNDATION):
    uid = str(cam.path)
    if uid == front_uid:
        front_idx = cam.index
    if uid == wrist_uid:
        wrist_idx = cam.index

if front_idx is None:
    raise SystemExit(f"front camera not found: {front_uid}")
if wrist_idx is None:
    raise SystemExit(f"wrist camera not found: {wrist_uid}")

print(front_idx, wrist_idx)
PY
)

echo "front index: $FRONT_INDEX"
echo "wrist index: $WRIST_INDEX"

lerobot-record \
  --robot.type=so101_follower \
  --robot.port=$FOLLOWER_PORT \
  --robot.id=my_awesome_follower_arm \
  --robot.cameras="{ front: {type: opencv, backend: 1200, index_or_path: $FRONT_INDEX, width: 1920, height: 1080, fps: 30}, wrist: {type: opencv, backend: 1200, index_or_path: $WRIST_INDEX, width: 1920, height: 1080, fps: 30}}" \
  --teleop.type=so101_leader \
  --teleop.port=$LEADER_PORT \
  --teleop.id=my_awesome_leader_arm \
  --display_data=true \
  --dataset.repo_id=local/record-test \
  --dataset.num_episodes=1 \
  --dataset.episode_time_s=20 \
  --dataset.reset_time_s=10 \
  --dataset.single_task="Grab the banana and place it into the bin" \
  --dataset.streaming_encoding=true \
  --dataset.encoder_threads=2 \
  --dataset.push_to_hub=False \
  $RESUME_FLAG
  
