# 在 UO101 机械臂上跑通遥操、微调和推理

## 一、 背景

## 二、适用环境

本文默认环境如下：

本地机器
  - macOS
  - Apple Silicon（M3 Pro）
  - conda / miniforge

UO101 机械臂
  - 两台本体，一台 Leader，一台 Follower（遥操时必要的两个角色）
    - 如果没有，那需要有台 3D 打印机（打印机器人部件参照[此教程](https://github.com/TheRobotStudio/SO-ARM100?tab=readme-ov-file#printing-the-parts)）
  - 12 块 [Feetech 电机](https://github.com/iotdesignshop/Feetech-tuna)（两台本体各需 6 块）

## 三、macOS 上准备 Ubuntu 环境

1. 从[官网](https://www.parallels.cn/products/desktop/download/)下载并安装 Parallels Desktop，这是 Mac 电脑上常用的虚拟机软件。
2. 在[官网](https://cdimage.ubuntu.com/releases/22.04/release/)选择`64-bit ARM (ARMv8/AArch64) server install image`下载 Ubuntu 22.04.5 LTS 的镜像`.iso`文件。
3. 在 Parallels Desktop 中从`.iso`手动安装 Ubuntu。都按默认选项来就好。
  <img width="984" height="696" alt="Screenshot 2026-03-17 at 11 12 06" src="https://github.com/user-attachments/assets/22e9e7fd-ccd7-4788-a6bc-68db1a7a1c59" />
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

## 四、UO101 机械臂组装

1. 先根据[教程](https://huggingface.co/docs/lerobot/so101#clean-parts) 组装好 Leader 和 Follower。其中注意每个电机组装前最好先接上一条线。
2. xxx

## 五、遥操

