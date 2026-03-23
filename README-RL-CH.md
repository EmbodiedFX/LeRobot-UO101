# 在 SO101 机械臂上跑通强化学习

> 本文位于 [https://github.com/EmbodiedFX/LeRobot-SO101](https://github.com/EmbodiedFX/LeRobot-SO101)，English version: [README-RL.md](README-RL.md)

## 一、 背景和适用环境

本文默认读者已完整跑通《[在 SO101 机械臂上跑通数据采集、模型微调和真机推理](https://github.com/EmbodiedFX/LeRobot-SO101/blob/main/README-CH.md)》的流程。
适用环境也同该教程的描述。

> 本教程主要参照[这个网页](https://huggingface.co/docs/lerobot/hilserl)制作。

## 二、MacBook 上的环境准备

在`lerobot`的 conda 环境里：

1. 安装额外需要的 Python 库：
  ```bash
  pip install -e ".[hilserl]"
  ```
2. 在[官方渠道]下载 SO101 机械臂的 URDF 文件，拷贝到`lerobot`项目目录，同时创建 `rl_config.json` 文件，通过以下方式：
  ```bash
  # 在`lerobot`项目外的一个路径
  git clone --branch main --single-branch git@github.com:TheRobotStudio/SO-ARM100.git
  export SO_PATH=<absolute path to SO-ARM100 root folder>

  # 然后打开 lerobot 项目根目录
  cp $SO_PATH/Simulation/SO101/so101_new_calib.urdf ./
  cp -r $SO_PATH/Simulation/SO101/assets ./
  vim rl_config.json  # 然后粘贴本仓库的 rl_config.json 全部内容，保存
  ```
4. 然后，运行如下命令，显示`RECORDING STARTED`后，模拟机械臂完成任务会达到的各种状态，以探测机械臂的活动范围边界：
  ```bash
  lerobot-find-joint-limits \
    --robot.type=so100_follower \
    --robot.port=$FOLLOWER_PORT \
    --robot.id=my_awesome_follower_arm \
    --teleop.type=so100_leader \
    --teleop.port=$LEADER_PORT \
    --teleop.id=my_awesome_leader_arm \
    --urdf_path=./so101_new_calib.urdf
  # urdf_path 参数中的 "./" 不能丢！否则会报错如“Error initializing kinematics: Mesh assets/base_motor_holder_so101_v1.stl could not be found.”

  # 最终的结果类似如下：
  # ========================================
  # FINAL RESULTS
  # ========================================
  
  # # End Effector Bounds (x, y, z):
  # max_ee = [0.3684, 0.1136, 0.3975]
  # min_ee = [0.0874, -0.1339, 0.0635]
  
  # # Joint Position Limits (radians):
  # max_pos = [62.9011, 47.956, 76.044, 101.2308, 50.5934, 96.2042]
  # min_pos = [-56.2198, -67.3846, -89.2308, 14.989, 2.8571, 3.0105]
  ```
5. 将上述得到的边界写入`rl_config.json`，如：
  ```json
  "end_effector_bounds": {
    "max": [0.36, 0.11, 0.39],
    "min": [0.08, -0.13, 0.06]
  }
  ```

## 三、离线数据集构建


