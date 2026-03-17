# 在 UO101 机械臂上跑通遥操、微调和推理

## 一、 背景

## 二、适用环境

本文默认环境如下：

本地机器
  - macOS
  - Apple Silicon（M3 Pro）
  - conda / miniforge

[UO101 机械臂](https://github.com/TheRobotStudio/SO-ARM100)
  - 两台本体，一台 Leader，一台 Follower（遥操时必要的两个角色）
    - 如果没有本体，可以使用 3D 打印机打印部件（参照[此教程](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#printing-the-parts)）
  - 每个本体还需要一块控制板，这个没法打印，需要参考这里的[渠道](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#sourcing-parts)买
  - 还需要 12 块 [Feetech 电机](https://github.com/iotdesignshop/Feetech-tuna)（两台本体各需 6 块），这个也没法打印

## 三、macOS 上准备 Ubuntu 虚拟机

1. 从[官网](https://www.parallels.cn/products/desktop/download/)下载并安装 Parallels Desktop，这是 Mac 电脑上常用的虚拟机软件。
2. 在[官网](https://cdimage.ubuntu.com/releases/22.04/release/)选择`64-bit ARM (ARMv8/AArch64) server install image`下载 Ubuntu 22.04.5 LTS 的镜像`.iso`文件。
3. 在 Parallels Desktop 中从`.iso`手动安装 Ubuntu。都按默认选项来就好。<img width="984" height="696" alt="Screenshot 2026-03-17 at 11 12 06" src="https://github.com/user-attachments/assets/22e9e7fd-ccd7-4788-a6bc-68db1a7a1c59" />
4. 安装完成后，在虚拟机的终端中安装`openssh`，并查看虚拟机的 IP 地址：
  ```bash
  sudo apt update
  sudo apt install openssh-server -y
  
  ip a
  ```

后面你就可以在 MacBook 的本地终端通过

```bash
ssh 你的用户名@虚拟机IP
```
远程连上 Ubuntu。使用本地终端，最大的好处是 macOS 上已经习惯的终端字体、键盘快捷键尤其是**剪切板使用方式**（比如从本地复制命令粘贴到虚拟机执行，或者反过来），一个也不用重新适应。

## 四、在 Ubuntu 中准备 LeRobot 环境

1. 先安装 Miniforge：
  ```bash
  wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
  bash Miniforge3-$(uname)-$(uname -m).sh
  ```
2. 安装完成后，重新打开 Ubuntu 的终端，参考[教程](https://huggingface.co/docs/lerobot/installation)创建环境：
  ```bash
  conda create -y -n lerobot python=3.12
  conda activate lerobot
  conda install ffmpeg -c conda-forge
  ```
3. 随后下载并安装`lerobot`：
  ```bash
  sudo apt-get update
  sudo apt-get install -y build-essential gcc python3-dev linux-headers-$(uname -r)
  python -m pip install -U pip setuptools wheel
  python -m pip install evdev

  git clone https://github.com/huggingface/lerobot.git
  cd lerobot
  pip install -e .
  ```

## 五、UO101 机械臂组装

1. 根据[教程](https://huggingface.co/docs/lerobot/so101#clean-parts)组装好 Leader 和 Follower，其中每个电机组装前最好先接上一条线。
2. 将每个本体的控制板连接上电源，并连接上 MacBook（在弹窗选择连到 Ubuntu 虚拟机）。特别地，第一次连接时，需要通过下面的命令确认每个本体控制板连的是哪个端口：
  ```bash
  lerobot-find-port
  # 随后根据弹出的文字操作
  ```
3. 而且往后每次连接电脑和控制板，都需要通过类似下面的命令授予端口的访问权限：
  ```bash
  sudo chmod a+rw /dev/ttyACM0
  sudo chmod a+rw /dev/ttyACM1
  ```
4. 根据[教程](https://huggingface.co/docs/lerobot/so101#2-set-the-motors-ids-and-baudrates)给两个本体的每个电机**设定 ID**（只需要设置一次），用到的命令大致如下（需要根据实际端口名称微调）：
  ```bash
  lerobot-setup-motors --robot.type=so101_follower --robot.port=/dev/ttyACM0
  lerobot-setup-motors --robot.type=so101_leader --robot.port=/dev/ttyACM1
  ```
5. 根据[教程](https://huggingface.co/docs/lerobot/so101#calibrate)校准两个本体（定位每个电机的工作范围），用到的命令大致如下（需要根据实际端口名称微调）：
  ```bash
  lerobot-calibrate --teleop.type=so101_follower --teleop.port=/dev/ttyACM0 --teleop.id=my_awesome_follower_arm
  lerobot-calibrate --teleop.type=so101_leader --teleop.port=/dev/ttyACM1 --teleop.id=my_awesome_leader_arm
  ```

### Trouble shooting

1. 如果出现：MacBook 连上串联的六个电机后，`lerobot-calibrate`命令第一次能跑，第二次却找不到个别电机（如出现错误`Missing motor IDs`），可行的解决方法是去修改`src/lerobot/motors/motors_bus.py`：
  ```python
  # 将下面这行
  model_nb = self.ping(id_)
  # 换成
  model_nb = self.ping(id_, num_retry=2)
  ```
这样做，如果可以解决，那对应的问题原因可以解释为：同一个端口一旦被 close 再 reopen，LeRobot/串口这条链路的“最前两笔通信”会出问题（边界上有残留/错位的串口状态或数据，导致最开始的两次 ping 被吃掉或解析错）。
2. 如果电机有连通性问题，可以用官方提供的脚本进行排查。具体参照[教程](https://github.com/iotdesignshop/Feetech-tuna)。

## 六、遥操与数据采集

1. 往 follower 装上摄像头，并连接 MacBook 。随后根据[教程](https://huggingface.co/docs/lerobot/il_robots?teleoperate_koch_camera=Command#find-your-camera)看是否能够找到它（注意区分 MacBook 本身的摄像头），记住它的 ID（如显示`Id: /dev/video2`的话，ID就是2）、分辨率和帧率信息。具体命令：
  ```bash
  lerobot-find-cameras opencv
  ```
2. 根据[教程](https://huggingface.co/docs/lerobot/il_robots#teleoperate-with-cameras)尝试遥操，用到的命令大致如下（需要根据实际端口名称和摄像头信息微调）：
  ```bash
  lerobot-teleoperate \
    --robot.type=so101_follower \
    --robot.port=/dev/ttyACM0 \
    --robot.id=my_awesome_follower_arm \
    --robot.cameras="{ front: {type: opencv, index_or_path: 2, width: 640, height: 480, fps: 30}}" \
    --teleop.type=so101_leader \
    --teleop.port=/dev/ttyACM1 \
    --teleop.id=my_awesome_leader_arm \
    --display_data=false
  ```
