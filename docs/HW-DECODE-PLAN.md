# 硬解 / 高分辨率改造计划

起点：上游 `rodri0x/ps5-airplay` v0.1.2（当前工作树）。
目标：4K + HEVC（硬解优先），并保留 1080p H.264 作为兜底。

## 现状盘点

| 位置 | 现状 | 结论 |
|---|---|---|
| `src/airplay_mirror.c:155` | 已经在识别到 HEVC SPS 时设置 `mirror->codec = 265` | 协议层不用改 |
| `src/h264_decoder.h` | `h264_decoder_submit(..., int codec, ...)` 已带 codec 参数 | 接口不用改 |
| `src/h264_decoder.cpp:150` | `if (codec != 264) return -2;` 直接把 265 拒掉 | 这里是要改的第一处 |
| `src/h264_decoder.cpp:81` | `avcodec_find_decoder(AV_CODEC_ID_H264)` 写死 | 改成按 codec 选解码器 |
| `third_party/ffmpeg/lib` | 预编译 FFmpeg 6.0，**只开了 h264 解码器** | 要重编，加 `--enable-decoder=hevc` |
| `src/ps5_video.c` | `tile_base()` 用 `s_width` 计算，尺寸参数化 | 4K 理论上能复用，需实测 |
| `src/ps5_video.h` | 已有 `ps5_video_present_i420()` 和 `present(bgra)` | NV12 输出需要加一个入口或做交错适配 |

**结论：协议层和显示层基本就绪，卡点集中在解码后端 + FFmpeg 构建。**

## 分三步

### 第 1 步：HEVC 软解（1080p）

1. 重编 `third_party/ffmpeg`：在原有 configure 上追加
   `--enable-decoder=hevc --enable-parser=hevc`
   （命令见 `third_party/ffmpeg/README.md`，需要 ps5-payload-sdk）
2. `h264_decoder.cpp`：
   - `ensure_decoder(int codec)` 按 264/265 选 `AV_CODEC_ID_H264` / `AV_CODEC_ID_HEVC`
   - `submit()` 接受 264 和 265
3. 实测 1080p60 HEVC 的 CPU 占用与掉帧（`-Os` 构建下预计 20–35% CPU）

### 第 2 步：4K

1. `control.c` / 能力上报：置 HEVC 的 feature bit，并把 display 尺寸报成 3840×2160
   （对照上游 UxPlay 的 `-h265`：feature bit 42 + `display[] = {3840,2160}`）
2. `ps5_video_init(3840, 2160)`：确认 tile 映射在 4K 下正确
   （4K 双缓冲 ≈ 66 MB，注意 DMEM 分配大小）
3. 提供开关：`max_res=1080p|4k`，默认 1080p

### 第 3 步：硬解（libSceVideodec2）

1. 新增 `src/ps5_videodec2.c`：封装 `sceVideodec2*`，输出 **NV12**
   - 已知细节：pitch 256、chroma 紧跟可见行（不是按 1088 对齐）
   - 参考实现：`MisterTemaki/MediaPlayerClassicPS5`（H.264 与 4K HEVC Main10 实测走主机解码器）
2. 解码后端抽象：`DECODER=soft|hw`，编译期选择，运行时可回退
3. `ps5_video_present_nv12()`：NV12 → tile 帧缓冲，省掉 YUV→RGBA 转换
4. 硬解失败（不支持的 profile/level）时自动回退软解

## 验收标准

| 阶段 | 判据 |
|---|---|
| 第 1 步 | 1080p60 HEVC 连续播放 5 分钟，掉帧率 < 1% |
| 第 2 步 | 4K30 HEVC 能稳定播放；4K60 允许降帧 |
| 第 3 步 | 同场景 CPU 占用从 30%+ 降到 < 5%，且 4K60 可行 |

## 构建前提

PS5 目标需要 Linux 环境（ps5-payload-sdk 的工具链是 bash 脚本 + Linux clang）：

- 本机：WSL2（未安装，需管理员执行 `wsl --install -d Ubuntu` 后重启）
- 或：GitHub Actions（`.github/workflows/release.yml` 已经存在，可直接用）
