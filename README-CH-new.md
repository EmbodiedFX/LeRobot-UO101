# 在 SO101 机械臂上跑通遥操、微调和推理

<img width="2048" height="1536" alt="image" src="https://github.com/user-attachments/assets/0fbf172c-a654-41e2-9d60-25f28cdeaf62" />


## 一、 背景

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
  - 还需要 12 块 [Feetech 电机](https://github.com/iotdesignshop/Feetech-tuna)（两台本体各需 6 块），这个也没法打印

摄像头
- 两个，一个拍全局信息（front），一个拍机械臂爪子（wrist）。需要有固定的地方或者能够固定在机械臂上。

## 三、在 MacBook 准备 LeRobot 环境

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
c
## 四、SO101 机械臂组装

1. 根据[教程](https://huggingface.co/docs/lerobot/so101#clean-parts)组装好 Leader 和 Follower，其中每个电机组装前最好先接上一条线。
2. 将每个本体的控制板连接上电源，并连接上 MacBook。随后通过下面的命令确认每个本体控制板连的是哪个端口：
  ```bash
  lerobot-find-port
  # 根据弹出的文字操作
  ```
3. 往后每次连接 MacBook 和控制板，都需要通过类似下面的命令授予端口的访问权限：
  ```bash
  sudo chmod a+rw /dev/tty.usbmodem5A7A0594001  # leader
  sudo chmod a+rw /dev/tty.usbmodem5A7C1172111  # follower
  ```
4. 根据[教程](https://huggingface.co/docs/lerobot/so101#2-set-the-motors-ids-and-baudrates)给两个本体的每个电机**设定 ID**（只需要设置一次），用到的命令大致如下（需要根据实际端口名称微调）：
  ```bash
  lerobot-setup-motors --robot.type=so101_follower --robot.port=/dev/tty.usbmodem5A7C1172111
  lerobot-setup-motors --teleop.type=so101_leader --teleop.port=/dev/tty.usbmodem5A7A0594001
  ```
5. 根据[教程](https://huggingface.co/docs/lerobot/so101#calibrate)校准两个本体——定位每个电机的工作范围（机械臂每连到一台新电脑做一次，因为校准生成的文件是存放到本地的），用到的命令大致如下（需要根据实际端口名称微调）：
  ```bash
  lerobot-calibrate --robot.type=so101_follower --robot.port=/dev/tty.usbmodem5A7C1172111 --robot.id=my_awesome_follower_arm
  lerobot-calibrate --teleop.type=so101_leader --teleop.port=/dev/tty.usbmodem5A7A0594001 --teleop.id=my_awesome_leader_arm
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

1. 分别装上两个摄像头（一个 front，一个 wrist），并将它们连接 MacBook。

通过插拔摄像头和执行以下命令确定它们的 UID

```bash
cat >/tmp/list_cams.swift <<'SWIFT'
import AVFoundation

for (i, d) in AVCaptureDevice.devices(for: .video).enumerated() {
    print("[\(i)] \(d.localizedName)\tUID=\(d.uniqueID)")
}
SWIFT

swift /tmp/list_cams.swift
```

比如最终的结论可能是：front 摄像头的 UID 是 `0x1400001bcf2cd1`，wrist 摄像头的 UID 是 `0x1300001bcf2cd1`。这个只需要确定一次，重新插拔不会改变。

在合适的目录新建如下 Python 脚本（命名为`teleop_macos.sh`）：

```python
#!/usr/bin/env bash
set -euo pipefail

FRONT_UID='把 front 相机的 uid 填这里'
WRIST_UID='把 wrist 相机的 uid 填这里'
FOLLOWER_PORT='把 follower 的端口路径填这里'
LEADER_PORT='把 leader 的端口路径填这里'

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

lerobot-teleoperate \
  --robot.type=so101_follower \
  --robot.port=$FOLLOWER_PORT \
  --robot.id=my_awesome_follower_arm \
  --robot.cameras="{ front: {type: opencv, backend: 1200, index_or_path: $FRONT_INDEX, width: 1920, height: 1080, fps: 30}, wrist: {type: opencv, backend: 1200, index_or_path: $WRIST_INDEX, width: 1920, height: 1080, fps: 30}}" \
  --teleop.type=so101_leader \
  --teleop.port=$LEADER_PORT \
  --teleop.id=my_awesome_leader_arm \
  --display_data=false
```

将`FRONT_UID``WRIST_UID``FOLLOWER_PORT``LEADER_PORT`修改成你的实际情况后，遥操就可以这样跑：

```bash
chmod +x teleop_macos.sh
./teleop_macos.sh
```

> 之所以要包到脚本里，而不是像[教程](https://huggingface.co/docs/lerobot/il_robots#teleoperate-with-cameras)那么整洁，是因为 MacBook 不同于 Ubuntu 等 Linux 系统，摄像头没有固定路径，且其 ID 也会随着调用而不固定、出现漂移的情况。唯一固定的是它们的 UID，因此脚本实际上就是先根据 UID 动态找到目标摄像头的 ID，然后再送给 `lerobot-teleoperate` 命令使用。

脚本里关于摄像头分辨率、帧率等的设定可以改。要看所支持的配置，可以先将新建下述脚本`cam_formats.swift`：

```swift
import Foundation
import AVFoundation
import CoreMedia

func fourCCString(_ code: FourCharCode) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    let s = bytes.map { b -> Character in
        if b >= 32 && b <= 126 {
            return Character(UnicodeScalar(b))
        } else {
            return "."
        }
    }
    return String(s)
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift cam_formats.swift <camera-uniqueID>\n", stderr)
    exit(2)
}

let uid = CommandLine.arguments[1]

guard let device = AVCaptureDevice(uniqueID: uid) else {
    fputs("camera not found for UID: \(uid)\n", stderr)
    exit(1)
}

print("name: \(device.localizedName)")
print("uid : \(device.uniqueID)")
print("formats:")

for (i, format) in device.formats.enumerated() {
    let desc = format.formatDescription
    let dims = CMVideoFormatDescriptionGetDimensions(desc)
    let subtype = CMFormatDescriptionGetMediaSubType(desc)
    let pixel = fourCCString(subtype)

    let fpsRanges = format.videoSupportedFrameRateRanges
        .map { r in
            String(format: "%.3f-%.3f fps", r.minFrameRate, r.maxFrameRate)
        }
        .joined(separator: ", ")

    print("[\(i)] \(dims.width)x\(dims.height)  pixel=\(pixel)  fps=\(fpsRanges)")
}
```

然后运行下述命令查看：

```bash
swift cam_formats.swift '摄像头的UID'
```

3. 遥操熟悉后，就可以开始采集数据。以“抓取一根香蕉为例并放进箱子为例”，先采集一个 episode：
  ```bash
  lerobot-record \
    --robot.type=so101_follower \
    --robot.port=/dev/ttyACM0 \
    --robot.id=my_awesome_follower_arm \
    --robot.cameras="{ front: {type: opencv, index_or_path: 4, width: 1920, height: 1080, fps: 30}, wrist: {type: opencv, index_or_path: 2, width: 1920, height: 1080, fps: 30}}" \
    --teleop.type=so101_leader \
    --teleop.port=/dev/ttyACM1 \
    --teleop.id=my_awesome_leader_arm \
    --display_data=false \
    --dataset.repo_id=samuel/record-test \
    --dataset.num_episodes=1 \
    --dataset.episode_time_s=20 \
    --dataset.reset_time_s=10 \
    --dataset.single_task="Grab the banana and place it into the bin" \
    --dataset.streaming_encoding=true \
    --dataset.encoder_threads=2 \
    --dataset.push_to_hub=False
  ```

  如果要回放这个 episode（机械臂复刻运动轨迹），可以使用下述命令：
  ```bash
  lerobot-replay \
    --robot.type=so101_follower \
    --robot.port=/dev/ttyACM0 \
    --robot.id=my_awesome_follower_arm \
    --dataset.repo_id=/home/samuel/.cache/huggingface/lerobot/samuel/record-test \
    --dataset.episode=0 \
    --play_sounds=false
  ```
4. 要继续采集，可以重新运行同样的命令并加`--resume=true`，也即：
  ```bash
    lerobot-replay \
    --robot.type=so101_follower \
    --robot.port=/dev/ttyACM0 \
    --robot.id=my_awesome_follower_arm \
    --dataset.repo_id=/home/samuel/.cache/huggingface/lerobot/samuel/record-test \
    --dataset.episode=0 \
    --play_sounds=false \
    --resume=true
  ```
