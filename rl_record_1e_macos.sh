#!/usr/bin/env bash
set -euo pipefail

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
  --env.robot.type=so101_follower \
  --env.robot.port=$FOLLOWER_PORT \
  --env.robot.id=my_awesome_follower_arm \
  --env.robot.cameras="{ front: {type: opencv, backend: 1200, index_or_path: $FRONT_INDEX, width: 640, height: 480, fps: 30}, wrist: {type: opencv, backend: 1200, index_or_path: $WRIST_INDEX, width: 640, height: 480, fps: 30}}" \
  --env.teleop.type=so101_leader \
  --env.teleop.port=$LEADER_PORT \
  --env.teleop.id=my_awesome_leader_arm \
  --env.teleop.use_gripper=true \
  --env.processor.control_mode=leader \
  --env.processor.observation.display_cameras=true \
  --env.processor.gripper.use_gripper=true \
  --env.processor.gripper.gripper_penalty=0 \
  --env.processor.reset.reset_time_s=10 \
  --env.processor.reset.control_time_s=20 \
  --dataset.repo_id=$RL_DATA_PATH \
  --dataset.task="pick_and_drop" \
  --dataset.num_episodes_to_record=15 \
  --dataset.push_to_hub=False \
  --mode=record
  
