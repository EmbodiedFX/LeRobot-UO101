# Running Data Collection, Model Fine-Tuning, and Real-World Inference on the SO101 Robotic Arm

> This article is located at [https://github.com/EmbodiedFX/LeRobot-SO101](https://github.com/EmbodiedFX/LeRobot-SO101). 中文版: [README-CH.md](README-CH.md)

This note records how, on a clean macOS Apple Silicon machine, to get the following three things working from scratch:

1. **Data collection**: first use a Leader arm to teleoperate a Follower arm, while recording demonstration trajectories with two cameras.
2. **Model fine-tuning**: then train an ACT model on those demonstration data.
3. **Real-world inference**: finally let the trained model read camera images and directly control the Follower arm to perform the task.

<img width="2048" height="1536" alt="image" src="https://github.com/user-attachments/assets/0fbf172c-a654-41e2-9d60-25f28cdeaf62" />


## 1. Background

What are the components mentioned in this article:

- **SO101** is the robotic arm hardware used in this setup.
- **LeRobot** is the toolchain that unifies models, datasets, and evaluation entry points.
- **ACT** is the VLA policy used here (52M parameters).

> If training and inference resources are sufficient, you can also switch to other models already supported by LeRobot, such as SmolVLA, π₀, π₀-FAST, π₀.₅, GR00T N1.5, X-VLA, and WALL-OSS. Guidance for these is also provided below.

## 2. Applicable Environment

This article assumes the following default environment:

Local machine
- macOS
- Apple Silicon (M3 Pro)
- conda / miniforge

[SO101 robotic arm](https://github.com/TheRobotStudio/SO-ARM100)
- Two arm bodies, one Leader and one Follower (the two roles required for teleoperation)
  - If you do not have the arm bodies, you can purchase ([sourcing channels](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#sourcing-parts)) or 3D-print the parts (refer to [this tutorial](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#printing-the-parts))
- Each arm body also requires a control board.
  - This cannot be printed; please purchase one ([sourcing channels](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#sourcing-parts)).
- You will also need 12 [Feetech motors](https://github.com/iotdesignshop/Feetech-tuna) (6 for each arm body)
  - Also, they cannot be printed and must be purchased ([sourcing channels](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#sourcing-parts)).

Cameras
- Two cameras: one for capturing the global scene (referred to later as “front”), and one for capturing the gripper area (referred to later as “wrist”). They need to be mounted somewhere fixed, or be attachable to the robotic arm.

## 3. Preparing the Python Environment for LeRobot on a MacBook

1. If the `conda` command is unavailable, you can first install Anaconda / Miniforge. Miniforge is used below as an example:
   ```bash
   wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
   bash Miniforge3-$(uname)-$(uname -m).sh
   ```

2. After installation, reopen the terminal and follow the [tutorial](https://huggingface.co/docs/lerobot/installation) to create the environment:

   ```bash
   conda create -y -n lerobot python=3.12
   conda activate lerobot
   conda install ffmpeg -c conda-forge
   ```
3. Then download and install `lerobot`:

   ```bash
   git clone https://github.com/huggingface/lerobot.git
   cd lerobot
   pip install -e .

   pip install -e ".[feetech]"  # motor-related
   pip install cv2-enumerate-cameras  # camera-related
   ```

## 4. Assembling the SO101 Robotic Arm

1. Assemble the Leader and Follower according to the [tutorial](https://huggingface.co/docs/lerobot/so101#clean-parts). It is best to connect a cable to each motor before assembly.
2. Connect each arm’s control board to power and to the MacBook. Then confirm which port each control board is connected to:

   ```bash
   # After this, you only need to redo it if the control board is connected to a new MacBook
   lerobot-find-port
   # Follow the instructions shown in the output
   ```
3. After confirming the ports, set them as environment variables for repeated use later:

   ```bash
   export LEADER_PORT=/dev/tty.usbmodem5A7A0594001
   export FOLLOWER_PORT=/dev/tty.usbmodem5A7C1172111
   ```
4. Grant access permissions to the ports:

   ```bash
   # Must be done every time the MacBook and control boards are connected
   sudo chmod a+rw $LEADER_PORT  # leader
   sudo chmod a+rw $FOLLOWER_PORT  # follower
   ```
5. According to the [tutorial](https://huggingface.co/docs/lerobot/so101#2-set-the-motors-ids-and-baudrates), **assign IDs** to each motor on both arm bodies:

   ```bash
   # After this, you only need to redo it if you change the motor connection order,
   # or replace a motor with a new one
   lerobot-setup-motors --robot.type=so101_follower --robot.port=$FOLLOWER_PORT
   lerobot-setup-motors --teleop.type=so101_leader --teleop.port=$LEADER_PORT
   ```
6. Calibrate both arm bodies according to the [tutorial](https://huggingface.co/docs/lerobot/so101#calibrate) (essentially determining the working range of each motor):

   ```bash
   # After this, you only need to redo it if the control board is connected to a new MacBook
   # --robot.id and --teleop.id can also be changed according to your preference,
   # but they must stay consistent with later commands
   lerobot-calibrate --robot.type=so101_follower --robot.port=$FOLLOWER_PORT --robot.id=my_awesome_follower_arm
   lerobot-calibrate --teleop.type=so101_leader --teleop.port=/$LEADER_PORT --teleop.id=my_awesome_leader_arm
   ```
7. Fix the robotic arms in suitable positions on the desk.

### Troubleshooting

1. If the following happens: after connecting the MacBook to the six daisy-chained motors, the `lerobot-calibrate` command works the first time, but the second time it cannot find some motors (for example showing the error `Missing motor IDs`), you can try modifying the `lerobot` source file `src/lerobot/motors/motors_bus.py`:

   ```python
   # Change this line
   model_nb = self.ping(id_)
   # To
   model_nb = self.ping(id_, num_retry=2)
   ```

> If this solves the problem, one possible explanation is: once the same port is closed and then reopened, the “first two communications” on the LeRobot/serial chain may fail (because of residual/misaligned serial state or data at the boundary), causing the first two ping attempts to be dropped or parsed incorrectly.

2. If the motors have connectivity issues, you can use the official diagnostic scripts for troubleshooting. See the [tutorial](https://github.com/iotdesignshop/Feetech-tuna) for details.

## 5. Teleoperation Trial and Data Collection

> The ultimate goal of this step is to collect task data that can be used to fine-tune the model.

1. Install the two cameras separately (one front, one wrist), and connect them to the MacBook. Then identify their UIDs by plugging and unplugging them and comparing the outputs of the following command:

   ```bash
   # Must be redone every time the cameras are connected to the MacBook,
   # because the UID is not fixed
   swift list_cams.swift
   ```
2. Set the identified UIDs as environment variables, for example:

   ```bash
   export FRONT_UID=0x21300001bcf2cd1
   export WRIST_UID=0x11200001bcf2cd1
   ```
3. Use a command like the following to try taking a picture, and adjust the cameras (especially the front camera) so that at 640x480 resolution, the captured image fully covers the workspace:

   ```bash
   ffmpeg -f avfoundation -framerate 30 -video_size 640x480 -i "0:none" -frames:v 1 test.jpg
   # Although you can use the system app `PhotoBooth` to view the camera in real time,
   # it usually uses the highest resolution and cannot be adjusted,
   # whereas later data collection here requires the field of view at 640x480
   ```
4. Next you can try teleoperation, using the leader arm to control the follower arm:

   ```bash
   chmod +x teleop_macos.sh  # only needs to be run once
   ./teleop_macos.sh
   ```
5. After becoming familiar with teleoperation, you can start collecting data. First determine the path where the data will be stored and set it as an environment variable (this path is relative to `$HF_HOME/lerobot` by default, where `$HF_HOME` defaults to `$HOME/.cache/huggingface`), for example:

   ```bash
   export TRAIN_DATA_PATH=local/record-test
   ```
6. Taking “pick up a banana and place it into a bin” as an example target task, you can collect one episode of data like this (an episode is one full execution of the task):

   ```bash
   chmod +x record_1e_macos.sh
   ./record_1e_macos.sh
   ```
7. The script hardcodes certain metadata. For example, the text instruction paired with the collected data is `dataset.single_task="Grab the banana and place it into the bin"`, and the duration of each episode is `dataset.episode_time_s=20`, etc. You can modify them as needed.
8. A sample of the data collected from one episode looks like this:

   ```
   (lerobot) EmbodiedFX@MacBook lerobot % tree ~/.cache/huggingface/lerobot/$TRAIN_DATA_PATH
   /Users/EmbodiedFX/.cache/huggingface/lerobot/local/record-test
   ├── data
   │   └── chunk-000
   │       └── file-000.parquet
   ├── meta
   │   ├── episodes
   │   │   └── chunk-000
   │   │       └── file-000.parquet
   │   ├── info.json
   │   ├── stats.json
   │   └── tasks.parquet
   └── videos
       ├── observation.images.front
       │   └── chunk-000
       │       └── file-000.mp4
       └── observation.images.wrist
           └── chunk-000
             └── file-000.mp4
   ```
9. After collecting the first episode, you can add the `resume` option to incrementally append another episode:

   ```bash
   ./record_1e_macos.sh --resume
   ```

The above scripts automatically launch software called `rerun.io`, which provides a more intuitive visualization of the data collection process and results:

<img width="1624" height="1010" alt="Screenshot 2026-03-19 at 13 36 41" src="https://github.com/user-attachments/assets/6fd54197-6e02-41c7-8d05-35952bcb214d" />

**Remarks**

1. During later model inference, the model can only see the video input from the cameras. So during data collection, it is best to watch the live captured video and perform action trajectories that can be completed **using only the video feed**—removing any privileged “god’s-eye view” that the model cannot learn.
2. The reason teleoperation and data collection are wrapped into scripts, rather than being as concise as in the [tutorial](https://huggingface.co/docs/lerobot/il_robots#teleoperate-with-cameras), is that cameras on a MacBook do not have fixed paths or IDs. Within a single connection session, the only stable identifier is their UID. Therefore a script is needed to first locate the cameras’ dynamic IDs by UID, and then pass those IDs to the `lerobot-teleoperate` and `lerobot-record` commands.
3. The settings in the script for camera resolution, frame rate, etc. can be changed (though higher is not always better: for inference, if the input video resolution is too high, model inference on a MacBook may be too slow to keep up; but if you later switch to a lower resolution, then having high-resolution training data and low-resolution inference input creates a mismatch that hurts generalization. So it is better to collect the data at the lower resolution that inference can actually support). To inspect the configurations supported by the camera itself, you can use the script `cam_formats.swift`:

   ```bash
   swift cam_formats.swift 'camera UID'
   ```
4. If, after reviewing the recordings (for example by manually inspecting the videos under `videos/observation.images.front`), you find that some episodes were collected incorrectly and do not want to keep them, you can delete them with the following command:

   ```
   lerobot-edit-dataset \
   --repo_id $TRAIN_DATA_PATH \
   --operation.type delete_episodes \
   --operation.episode_indices "[index1, index2, ...]"
   ```

# 6. Model Training

> The time estimates below are based on 30 episodes of data (collected by running the original `record_1e_macos.sh` 30 times). If you change the camera resolution, amount of data, etc., the estimates will differ.

First, determine the path where the model will be stored (relative to the current working directory) and set it as an environment variable, for example:

```bash
export POLICY_PATH=outputs/train/act_so101_test
```

Then, depending on the resources you have available, there are the following options:

## (1) Train on a MacBook

Train with a command like the following:

```bash
lerobot-train \
  --dataset.repo_id=$TRAIN_DATA_PATH \
  --policy.type=act \
  --output_dir=$POLICY_PATH \
  --policy.device=mps \
  --policy.push_to_hub=False \
  --wandb.enable=false \
  --batch_size=1 \
  --num_workers=0
```

It does run in practice (`batch_size=1`), but is estimated to take about 4 hours.

## (2) Train on an Ubuntu Server

Copy the training data from the MacBook to the server, and set `TRAIN_DATA_PATH` there as well (again, relative to `$HF_HOME/lerobot`), for example:

```bash
export TRAIN_DATA_PATH=local/record-test
```

For single-GPU training, use a command like:

```bash
lerobot-train \
  --dataset.repo_id=$TRAIN_DATA_PATH \
  --policy.type=act \
  --output_dir=$POLICY_PATH \
  --policy.device=cuda \
  --policy.push_to_hub=False \
  --wandb.enable=false \
  --batch_size=8
```

For multi-GPU training, use a command like the following (`num_processes × batch_size` gives the **effective batch size**—which is 8 here):

```bash
accelerate launch \
  --multi_gpu \
  --num_processes=8 \
  $(which lerobot-train) \
  --dataset.repo_id=$TRAIN_DATA_PATH \
  --policy.type=act \
  --output_dir=$POLICY_PATH \
  --policy.device=cuda \
  --policy.push_to_hub=false \
  --wandb.enable=false \
  --batch_size=1
```

By default, training runs for 100,000 steps. In practice, it took 2.25 hours on 8× H100 GPUs, with about 3 GB of memory used per GPU.

After training is complete, copy the model from the server’s `POLICY_PATH` back to the MacBook’s `POLICY_PATH`. Since the `$POLICY_PATH` directory contains intermediate states and training dynamics that are unnecessary for inference, you can save storage space by preserving the directory structure while copying only the contents of the `$POLICY_PATH/checkpoints/last/pretrained_model` subdirectory.


**Remarks**

1. The `lerobot` environment and scripts support W&B natively. If you want to use W&B to visualize the training process (training dynamics, system resource usage), you can first log in from the terminal:

```bash
export WANDB_API_KEY=<your W&B API key>
# On a corporate network you may also need: export WANDB_INSECURE_DISABLE_SSL=true
wandb login
```

Then replace `--wandb.enable=false` in the training command with the following as needed:

```bash
  --wandb.enable=true \
  --wandb.project=<your_project_name)> \
  --wandb.entity=<your_team_name> \
  --wandb.notes="act banana baseline" \
```

<img width="5056" height="3456" alt="W B Chart 3_19_2026, 1_24_41 PM" src="https://github.com/user-attachments/assets/cee1df19-f20a-4bbe-887c-d15de93a5145" />

2. In addition to ACT, LeRobot also supports other models such as SmolVLA, π₀, π₀-FAST, π₀.₅, GR00T N1.5, X-VLA, and WALL-OSS. They have different training and inference resource requirements. The table below provides a brief comparison.

| Model |                 Reference                 | Parameter Count in LeRobot |                   Training Argument                  | Training VRAM | Time for 100k Steps (8× H100; 8 episodes per step) | MacBook Inference Experience |
| :---: | :---------------------------------------: | :------------------------: | :--------------------------------------------------: | :-----------: | :--------------------------------------------------: | :--------------------------: |
|  ACT  | [Paper](https://arxiv.org/abs/2304.13705) |             52M            |                  `--policy.type=act`                 |  3 GB per GPU |                        2.25 h                        |            Smooth            |
|  π₀.₅ | [Paper](https://arxiv.org/abs/2504.16054) |             4B             | `--policy.type=pi05 --policy.train_expert_only=true` | 29 GB per GPU |                          4 h                         |              TBD             |


# 7. Using the Model on a MacBook to Control the Robotic Arm

Determine the path where inference data will be stored (inference can also be considered a form of data collection; this path is also relative to `$HF_HOME/lerobot` by default), and set it as an environment variable, for example:

```bash
export EVAL_DATA_PATH=local/eval_so100
```

Then make sure the follower robotic arm and both cameras are connected to the MacBook, and run the script to try one inference episode:

```bash
chmod +x eval_1e_macos.sh
./eval_1e_macos.sh
```
