# 在 SO101 机械臂上跑通数据采集、模型微调和真机推理

> 本文位于 [https://github.com/EmbodiedFX/LeRobot-SO101](https://github.com/EmbodiedFX/LeRobot-SO101)，English version: [README.md](README.md)

这篇笔记记录的是：在一台干净的 macOS Apple Silicon 机器上，如何从零开始跑通下面三件事：
1. **数据采集**：先用一台 Leader 臂遥操一台 Follower 臂，配合两个摄像头录下示范轨迹。
2. **模型微调**：再用这些示范数据训练一个 ACT 模型。
3. **真机推理**：最后让训练好的模型读取摄像头画面，直接控制 Follower 机械臂执行任务。

<img width="2048" height="1536" alt="image" src="https://github.com/user-attachments/assets/0fbf172c-a654-41e2-9d60-25f28cdeaf62" />


## 一、 背景

本文提到的组件分别是什么：

- **SO101** 是本次使用的机械臂本体。
- **LeRobot** 是把模型、数据集、评测入口统一起来的工具链。
- **ACT** 是本次使用的 VLA policy（52M参数）。

> 训练和推理资源够的话，还可以换成 LeRobot 有现成支持的其他模型：SmolVLA、π₀、π₀-FAST、π₀.₅ 、GR00T N1.5、X-VLA、WALL-OSS 等。下文也有指引。

## 二、适用环境

本文默认环境如下：

本地机器
  - macOS
  - Apple Silicon（M3 Pro）
  - conda / miniforge

[SO101 机械臂](https://github.com/TheRobotStudio/SO-ARM100)
  - 两台本体，一台 Leader，一台 Follower（遥操时必要的两个角色）
    - 如果没有本体，可以购买（[渠道](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#sourcing-parts)）或使用 3D 打印机打印部件（参照[此教程](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#printing-the-parts)）
  - 每个本体还需要一块控制板
    - 这个没法打印，需要买（[渠道](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#sourcing-parts)）
  - 还需要 12 块 [Feetech 电机](https://github.com/iotdesignshop/Feetech-tuna)（两台本体各 6 块）
    - 也没法打印，需要购买（[渠道](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#sourcing-parts)）

摄像头
- 两个，一个拍全局信息（后面称为“front”），一个拍机械臂爪子（后面称为“wrist”）。需要有固定的地方或者能够固定在机械臂上。

## 三、在 MacBook 准备 LeRobot 所需的 Python 环境

1. 如果`conda`命令不可用，可以先安装 Anaconda / Miniforge。下面以 Miniforge 为例：
  ```bash
  wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
  bash Miniforge3-$(uname)-$(uname -m).sh
  ```
2. 安装完成后，重新打开的终端，参考[教程](https://huggingface.co/docs/lerobot/installation)创建环境：
  ```bash
  conda create -y -n lerobot python=3.12
  conda activate lerobot
  conda install ffmpeg -c conda-forge
  ```
3. 随后下载并安装`lerobot`：
  ```bash
  git clone https://github.com/huggingface/lerobot.git
  cd lerobot
  pip install -e .

  pip install -e ".[feetech]"  # 电机相关
  pip install cv2-enumerate-cameras  # 摄像头相关
  ```

## 四、SO101 机械臂组装

1. 根据[教程](https://huggingface.co/docs/lerobot/so101#clean-parts)组装好 Leader 和 Follower，其中每个电机组装前最好先接上一条线。
2. 将每个本体的控制板连接上电源，并连接上 MacBook。随后确认每个本体控制板连的是哪个端口：
  ```bash
  # 此后，若控制板连接新 MacBook 才需要重做一次
  lerobot-find-port
  # 根据弹出的文字操作
  ```
3. 确认后，设置成环境变量，以供后面反复使用：
  ```bash
  export LEADER_PORT=/dev/tty.usbmodem5A7A0594001
  export FOLLOWER_PORT=/dev/tty.usbmodem5A7C1172111
  ```
4. 授予端口的访问权限：
  ```bash
  # 每次连接 MacBook 和控制板都要做
  sudo chmod a+rw $LEADER_PORT  # leader
  sudo chmod a+rw $FOLLOWER_PORT  # follower
  ```
5. 根据[教程](https://huggingface.co/docs/lerobot/so101#2-set-the-motors-ids-and-baudrates)给两个本体的每个电机**设定 ID**：
  ```bash
  # 此后，若重新调整电机的连接顺序、或更换新的电机才需要重做一次
  lerobot-setup-motors --robot.type=so101_follower --robot.port=$FOLLOWER_PORT
  lerobot-setup-motors --teleop.type=so101_leader --teleop.port=$LEADER_PORT
  ```
6. 根据[教程](https://huggingface.co/docs/lerobot/so101#calibrate)校准两个本体（本质上是定位每个电机的工作范围）：
  ```bash
  # 此后，若控制板连接新 MacBook 才需要重做一次
  # --robot.id 和 --teleop.id 也可以根据你的喜好更改，但要和后面命令使用的保持一致
  lerobot-calibrate --robot.type=so101_follower --robot.port=$FOLLOWER_PORT --robot.id=my_awesome_follower_arm
  lerobot-calibrate --teleop.type=so101_leader --teleop.port=/$LEADER_PORT --teleop.id=my_awesome_leader_arm
  ```
7. 将机械臂固定在桌子的合适位置。

### Troubleshooting

1. 如果出现：MacBook 连上串联的六个电机后，`lerobot-calibrate`命令第一次能跑，第二次却找不到个别电机（如出现错误`Missing motor IDs`），可以尝试修改 lerobot 源码`src/lerobot/motors/motors_bus.py`：
  ```python
  # 将下面这行
  model_nb = self.ping(id_)
  # 换成
  model_nb = self.ping(id_, num_retry=2)
  ```
> 这样做如果可以解决，那对应的问题原因可以解释为：同一个端口一旦被 close 再 reopen，LeRobot/串口这条链路的“最前两笔通信”会出问题（边界上有残留/错位的串口状态或数据，导致最开始的两次 ping 被吃掉或解析错）。

2. 如果电机有连通性问题，可以用官方提供的脚本进行排查。具体参照[教程](https://github.com/iotdesignshop/Feetech-tuna)。

## 五、遥操尝试与数据采集

> 本步的终极目标是采集出能够用来微调模型的任务数据。

1. 分别安装好两个摄像头（一个 front，一个 wrist），并将它们连接 MacBook。随后通过插拔摄像头和对比以下命令的运行结果来分别确定它们的 UID：
  ```bash
  # 每次连接摄像头和 MacBook 都需要重做一次，因为 UID 不固定
  swift list_cams.swift
  ```
2. 将确定的 UID 设置为环境变量，如：
  ```bash
  export FRONT_UID=0x21300001bcf2cd1
  export WRIST_UID=0x11200001bcf2cd1
  ```
3. 使用类似下面的命令尝试拍照，调整摄像头（尤其是 front）的视野使得 640x480 的分辨率拍出来的照片完整包含工作区：
  ```bash
  ffmpeg -f avfoundation -framerate 30 -video_size 640x480 -i "0:none" -frames:v 1 test.jpg
  # 虽然使用`PhotoBooth`系统应用能实时观看摄像头的视野，但是其分辨率一般拉到最高，且不能调整，而这边后续采集数据需要的是 640x480 分辨率下的视野
  ```
4. 接下来可以尝试遥操，即用主机械臂控制从机械臂： 
  ```bash
  chmod +x teleop_macos.sh  # 只需跑一次
  ./teleop_macos.sh
  ```
5. 遥操熟悉后，就可以开始采集数据。先确定数据的存放路径并设置环境变量（这个路径默认相对于`$HF_HOME/lerobot`，其中`$HF_HOME`默认为`$HOME/.cache/huggingface`），如：
  ```bash
  export TRAIN_DATA_PATH=local/record-test
  ```
6. 以“抓取一根香蕉为例并放进箱子”为目标任务，可以这样采集一集数据（集，episode，就是完成一次任务的过程）：
  ```bash
  chmod +x record_1e_macos.sh
  ./record_1e_macos.sh
  ```
7. 脚本里硬编码了若干元信息。如将与采集数据配对的文本指令 `dataset.single_task="Grab the banana and place it into the bin"`，又如每集采集的时长`dataset.episode_time_s=20`等。可以按需修改。
8. 一集采集出来的数据样例如下：
  ```
  (lerobot) EmbodiedFX@MacBook lerobot % tree ~/.cache/huggingface/lerobot/$TRAIN_DATA_PATH
  /Users/EmbodiedFX/.cache/huggingface/lerobot/local/record-test
  ├── data
  │   └── chunk-000
  │       └── file-000.parquet
  ├── meta
  │   ├── episodes
  │   │   └── chunk-000
  │   │       └── file-000.parquet
  │   ├── info.json
  │   ├── stats.json
  │   └── tasks.parquet
  └── videos
      ├── observation.images.front
      │   └── chunk-000
      │       └── file-000.mp4
      └── observation.images.wrist
          └── chunk-000
            └── file-000.mp4
  ```
9. 采集完第一集数据后，后续可以添加`resume`选项，增量地添加一集数据：
  ```bash
  ./record_1e_macos.sh --resume
  ```

上述脚本会自动调用名为`rerun.io`的软件，可以更直观地可视化数据的采集过程和结果：

<img width="1624" height="1010" alt="Screenshot 2026-03-19 at 13 36 41" src="https://github.com/user-attachments/assets/6fd54197-6e02-41c7-8d05-35952bcb214d" />


**Remarks**

1. 后续模型推理只能看到摄像头的视频输入，所以采集数据时，最好看着实时捕获的视频，采取**只看视频画面也能完成任务**的动作路径——去除模型学不到的上帝视角。 
2. 之所以遥操和数据采集要包到脚本里，而不是像[教程](https://huggingface.co/docs/lerobot/il_robots#teleoperate-with-cameras)那样简洁，是因为 MacBook 中摄像头没有固定路径和ID，单次插入中唯一固定的是它们的 UID。因此需要一个脚本，先根据 UID 找到目标摄像头的动态 ID，然后再送给`lerobot-teleoperate`和`lerobot-record`命令使用。
3. 脚本里关于摄像头分辨率、帧率等的设定可以改（不过并非越高越好：考虑到推理时，如果输入视频分辨率太高，MacBook 上模型推理速度可能跟不上而无法进行；而如果到时候换用更低的分辨率，那么训练数据分辨率高、推理输入分辨率低，这个不一致会导致模型泛化性差。所以还不如采集数据的时候就使用推理所支持的低分辨率）。要看摄像头本身所支持的配置，可以使用脚本`cam_formats.swift`：
  ```bash
  swift cam_formats.swift '摄像头的UID'
  ```
4. 如果看回放（比如手动审视 `videos/observation.images.front` 里面的视频）后发现某几集数据采错了、不想要，可以通过下面的命令删掉：
  ```
  lerobot-edit-dataset \
  --repo_id $TRAIN_DATA_PATH \
  --operation.type delete_episodes \
  --operation.episode_indices "[索引1, 索引2, 等等]"
   ```

# 六、模型训练

> 下面预估时间基于 30 集的数据量（使用原版`record_1e_macos.sh`采集30次）。如果更改了相机分辨率、数据量等，预估时间会不一样。

首先，确定模型存放的路径（相对于当前工作目录）并设置环境变量，如：

```bash
export POLICY_PATH=outputs/train/act_so101_test
```

然后，取决于你手边的资源，有如下述选项：

## （一）在 MacBook 上训练

使用形如下列的命令训练：

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

亲测跑得动（`batch_size=1`），但是预估需要4小时左右。

## (二) 在 Ubuntu 服务器上训练

把训练数据从 MacBook 拷贝到服务器上，并设置好那边的`TRAIN_DATA_PATH`(again，相对于`$HF_HOME/lerobot`)，如：

```bash
export TRAIN_DATA_PATH=local/record-test
```

单卡的话，使用形如以下命令训练：

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

多卡可使用形如以下命令训练（`num_processes`和`batch_size`的乘积为 **effective batch size**——此处为 8）：

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

默认训练10万步。亲测8卡H100上2.25小时完成，每张卡约占用3GB内存。

训练结束后，模型从服务器的`POLICY_PATH`拷贝回 MacBook 的`POLICY_PATH`路径。因为`$POLICY_PATH`目录包含中间状态和训练动态，推理是不必要的。为了节省存储空间，可以保留目录层次结构地拷贝`$POLICY_PATH/checkpoints/last/pretrained_model`这个子目录的内容。

**Remarks**

1. lerobot 环境和脚本天然支持 W&B。如果需要使用 W&B 可视化训练过程（训练动态、系统资源使用情况），可以先在终端登陆

```bash
export WANDB_API_KEY=<你的 W&B API key>
# 公司网络里也许需要：export WANDB_INSECURE_DISABLE_SSL=true
wandb login
```

然后将训练命令中的`--wandb.enable=false`参数按需换成：

```bash
  --wandb.enable=true \
  --wandb.project=<your_project_name)> \
  --wandb.entity=<your_team_name> \
  --wandb.notes="act banana baseline" \
```

<img width="5056" height="3456" alt="W B Chart 3_19_2026, 1_24_41 PM" src="https://github.com/user-attachments/assets/cee1df19-f20a-4bbe-887c-d15de93a5145" />

2. 除了 ACT，LeRobot 还适配其他模型：SmolVLA、π₀、π₀-FAST、π₀.₅ 、GR00T N1.5、X-VLA、WALL-OSS 等。它们对训练和推理的资源有不同的要求，下面是简单对比的表格：

| 模型 | 参考 | LeRobot实现的参数量 | 训练传参 | 训练显存 | 8卡H100训练10万步时长（每步8集） | MacBook推理体感 |
|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| ACT | [论文](https://arxiv.org/abs/2304.13705) | 52M | --policy.type=act | 3GB每卡 | 2.25h | 流畅 |
| π₀.₅ | [论文](https://arxiv.org/abs/2504.16054) | 4B | --policy.type=pi05 --policy.train_expert_only=true | 29B每卡 | 4h | 待定 |

# 七、MacBook 上模型推理控制机械臂

确定推理数据的存放路径（推理也可以认为是一种数据采集的过程；这个路径也是默认相对于`$HF_HOME/lerobot`），设置环境变量如

```bash
export EVAL_DATA_PATH=local/eval_so100
```

然后确保 follower 机械臂及两个摄像头与 MacBook 连通后，运行脚本，尝试一集推理：

```bash
chmod +x eval_1e_macos.sh
./eval_1e_macos.sh
```
