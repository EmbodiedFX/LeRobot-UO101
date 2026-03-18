# 在 SO101 机械臂上跑通数据采集、模型微调和真机推理

> 本文位于 [https://github.com/EmbodiedFX/LeRobot-SO101](https://github.com/EmbodiedFX/LeRobot-SO101)，English version: [README.md](README.md)

这篇笔记记录的是：在一台干净的 macOS Apple Silicon 机器上，如何从零开始跑通下面三件事：
1. **数据采集**：xxx
2. **模型微调**：yyy
3. **真机推理**：zzz

<img width="2048" height="1536" alt="image" src="https://github.com/user-attachments/assets/0fbf172c-a654-41e2-9d60-25f28cdeaf62" />


## 一、 背景

本文提到的组件分别是什么：

- **SO101** 是本次使用的机械臂本体。
- **LeRobot** 是把模型、数据集、评测入口统一起来的工具链。
- **ACT** 是本次使用的 VLA policy。

## 二、适用环境

本文默认环境如下：

本地机器
  - macOS
  - Apple Silicon（M3 Pro）
  - conda / miniforge

[SO101 机械臂](https://github.com/TheRobotStudio/SO-ARM100)
  - 两台本体，一台 Leader，一台 Follower（遥操时必要的两个角色）
    - 如果没有本体，可以使用 3D 打印机打印部件（参照[此教程](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#printing-the-parts)）
  - 每个本体还需要一块控制板，这个没法打印，需要参考这里的[渠道](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#sourcing-parts)买
  - 还需要 12 块 [Feetech 电机](https://github.com/iotdesignshop/Feetech-tuna)（两台本体各 6 块），也没法打印需要购买

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

### Trouble shooting

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

1. 分别装上两个摄像头（一个 front，一个 wrist），并将它们连接 MacBook。随后通过插拔摄像头和对比以下命令的运行结果来分别确定它们的 UID：
  ```bash
  # 每次连接摄像头和 MacBook 都需要重做一次，因为 UID 不固定
  swift list_cams.swift
  ```
2. 将确定的 UID 设置为环境变量，以供后面反复使用：
  ```bash
  export FRONT_UID=0x21300001bcf2cd1
  export WRIST_UID=0x11200001bcf2cd1
  ```
3. 接下来可以尝试遥操，即用主机械臂控制从机械臂： 
  ```bash
  chmod +x teleop_macos.sh
  ./teleop_macos.sh
  ```
4. 遥操熟悉后，就可以开始采集数据。比如，以“抓取一根香蕉为例并放进箱子”为目标任务，可以这样采集一集数据（就是完成一次任务的过程）：
  ```bash
  chmod +x record_1e_macos.sh
  ./record_1e_macos.sh
  # 脚本里写死了若干任务元信息
  # 如将与采集数据配对的文本指令 "Grab the banana and place it into the bin"
  # 又如数据集保存的相对路径 local/record-test
  # 后续如要为新任务采集数据、或更改某些参数，以其为模板修改相关项即可
  ```
5. 默认设置下，采集出来的数据会在`~/.cache/huggingface/lerobot/local/record-test`。一集的数据包含以下内容：
  ```
  (lerobot) EmbodiedFX@MacBook lerobot % tree ~/.cache/huggingface/lerobot/local/record-test
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
6. 可以执行下面的命令来增量地添加一集数据：
  ```bash
  ./record_1e_macos.sh --append
  ```

上述脚本会自动调用`rerun.io`，可以更直观地可视化每集数据的采集过程：

<img width="1624" height="1010" alt="Screenshot 2026-03-18 at 18 36 27" src="https://github.com/user-attachments/assets/9ef7f990-d2b4-474a-b3b7-0cd506dae9a7" />

**Remarks**

1. 后续模型推理只能看到摄像头的视频输入，所以采集数据时，最好看着实时捕获的视频，采取**只看视频画面也能完成任务**的动作路径——去除模型学不到的上帝视角。 
2. 之所以遥操要包到脚本里，而不是像[教程](https://huggingface.co/docs/lerobot/il_robots#teleoperate-with-cameras)那样简洁，是因为 MacBook 不同于 Ubuntu 等，摄像头没有固定路径，且 ID 也会随着调用而出现漂移的情况，唯一固定的是它们的 UID。因此需要个脚本，先根据 UID 动态找到目标摄像头的 ID，然后再送给 `lerobot-teleoperate` 命令使用。数据采集同理。
3. 脚本里关于摄像头分辨率、帧率等的设定可以改。要看摄像头本身所支持的配置，可以使用脚本`cam_formats.swift`：
  ```bash
  swift cam_formats.swift '摄像头的UID'
  ```
