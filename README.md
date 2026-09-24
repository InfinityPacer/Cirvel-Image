# Cirvel

为你的媒体库而生。

STRM 即本地，完整媒体信息，直连播放，零转码。

适用于 Plex Media Server，基于 LinuxServer 镜像构建，客户端、遥控、共享与 plex.tv
的行为都不变。

```sh
docker pull ghcr.io/infinitypacer/cirvel:latest
docker pull infinitypacer/cirvel:latest
```

也可以指定版本。

```sh
docker pull ghcr.io/infinitypacer/cirvel:0.1.0
docker pull infinitypacer/cirvel:0.1.0
```

**本版本内置 Plex Media Server 1.43.4.10903。**

## 它做什么

Plex 原本不认识 `.strm`，要么识别不了媒体信息，要么由服务器下载整个文件再转码
推给客户端，NAS 的上行带宽与 CPU 全部被占住。Cirvel 改变这两件事。

- **媒体信息**：直接探测 STRM 指向的远端媒体，把时长、分辨率、编码、音轨与字幕
  写进 Plex 的媒体库，条目在界面上与本地媒体无异。
- **播放**：改写播放决策，让客户端拿到 CDN 地址后自己去取流。服务器不参与传输，
  也不启动转码。

默认情况下服务器不会为任何用途读取 STRM 的远端媒体。需要服务器端转码或片头片尾
检测时，在 Plex 设置页的 **Cirvel** 条目里按用途逐项授权。

## 能力

| 能力 | 说明 |
| --- | --- |
| 远端媒体信息 | STRM 条目带有时长、分辨率、编码、码率、音轨与字幕，在界面上与本地媒体无异 |
| 客户端直连播放 | STRM 由客户端直接连接 CDN 播放，服务器不中转、不转码 |
| 本地媒体不受影响 | 非 STRM 的条目行为与原生 Plex 一致 |
| 服务端读取授权 | 默认不为任何用途下载 STRM 媒体，需要时按用途逐项开启 |
| 探测速率控制 | 媒体信息探测的速率可调 |
| 可视化配置 | Plex 设置页内的独立条目，保存即生效 |
| 诊断 | 独立日志，容器健康检查覆盖 Plex 与 Cirvel |

## 免费版与 Pro

STRM 播放本身永久免费，Pro 让整个媒体库提前准备好，并提供更多高级能力。

### 功能对比

| 功能 | 免费版 | Pro |
| --- | :---: | :---: |
| **STRM 直连播放**：客户端直接从 CDN 取流，NAS 不中转、不转码 | ✅ | ✅ |
| **打开即探测**：打开或播放某一集时，自动读取它的时长、音轨与字幕 | ✅ | ✅ |
| **浏览不等待**：一次打开整季时不排队卡住，来不及探测的交给后台完成 | ✅ | ✅ |
| **媒体信息保护**：Plex 刷新元数据后，已有的媒体信息自动恢复，无需重新读取 | ✅ | ✅ |
| **云盘访问保护**：限速与遇到限流时自动退避，降低云盘账号风控风险 | ✅ | ✅ |
| **后台补齐**：按计划自动分析整个媒体库，所有条目提前显示分辨率、HDR、音轨与字幕 | — | ✅ |
| **批量分析**：在 Plex 中分析整季、整部剧或整个媒体库 | — | ✅ |
| **远端校验**：定期确认远端文件没有变化，变了自动重新分析 | — | ✅ |
| **本地复用**：已有同名本地文件时直接复用它的媒体信息，不访问云盘 | — | ✅ |
| **服务端读取**：浏览器等不能直连的客户端可由服务器转码播放 STRM，并支持片头片尾检测 | — | ✅ |

设置页的「许可」区块会显示媒体库中已分析与未分析的 STRM 数量。

### 免费版的实际体验

- 新入库的 STRM 条目一开始没有分辨率、音轨等信息。第一次打开时读取，通常一秒左右，
  随后即可播放。
- 在 Plex 中对整季或整个媒体库点「分析」不会批量读取，条目在被打开时逐个补上。
- 每小时最多读取 60 个条目，正常浏览与播放用不完，超出的条目在下一次打开时再读取。
- 已经读取过的信息会一直保留，Plex 刷新元数据也不会丢失。

### Pro 的实际体验

- 整个媒体库在后台提前分析完成，任何客户端打开时信息都已齐全，可以按分辨率、HDR
  等条件筛选。
- 有同名本地文件的条目不访问云盘，远端文件变化会被自动发现。
- 浏览器、远程低带宽等不能直连的场景，可以开启服务器转码播放 STRM。

### 授权

- 一次性购买，包含后续更新，不提供试用。
- 授权码在 Plex 设置页的 Cirvel 条目中激活，绑定服务器所属的 Plex 账号，不限服务器
  数量，绑定后不可更换账号。
- 续期或升级时，在同一位置输入新的授权码即可替换当前授权。到期更早的授权码不会替换
  当前授权。
- 激活后需要能定期连接许可服务续期。连续 48 小时无法连接时暂时回到免费版，恢复连接后
  自动恢复 Pro。
- Pro 失效时，已分析的媒体信息与已保存的 Pro 设置都会保留，重新激活后立即生效。

## 部署

沿用 LinuxServer Plex 的既有方式即可，同样的 `/config`、同样的 `32400:32400`、
`host` 与 `bridge` 网络都不需要额外配置。

```yaml
services:
  plex:
    image: ghcr.io/infinitypacer/cirvel:latest
    container_name: plex
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - VERSION=docker
    volumes:
      - ./app_data/config:/config
      - ./app_data/transcode:/transcode
      - /path/to/media:/data:ro
    ports:
      - 32400:32400
    restart: unless-stopped
```

媒体路径在容器内必须与 STRM 文件被扫描时的路径一致。

## 配置

运行期可调项都在 Plex 设置页左侧「设置」分组末尾的 **Cirvel** 条目里，
保存即生效，无需重启容器，配置随 `/config` 卷持久化。打开该页面需要 Plex
服务器拥有者权限，由 Plex 自身判定。

## 版本与更新

tag 只表示 Cirvel 自己的版本（`0.1.0`、`latest`），与 Plex 的版本号无关。

内置的 Plex 是固定的，每个版本使用一个经过验证的 Plex Media Server，**不随 Plex
的发布自动更新**。升级 Plex 属于 Cirvel 的一次版本变更，会在发布说明里写明
新的 Plex 版本，本页顶部的版本号也会同步。镜像的 `io.infinitypacer.cirvel.plex.version`
标签始终记录当前内置的 Plex 版本，可用 `docker inspect` 查询。

这意味着容器不会自己把 Plex 升上去。想要新的 Plex，拉新版 Cirvel。

## 支持范围

`linux/amd64` 与 `linux/arm64`。源码不在本仓库，这里只做镜像打包与发布。

## 使用须知

- **合法的 Plex 与媒体来源**：Cirvel 只适用于合法安装和使用 Plex Media Server 的用户。
  Cirvel 不提供、不索引、不分发任何影音内容。STRM 指向什么由你决定，你应确保对所
  访问的媒体及其存储服务拥有相应权利，并遵守该存储服务的使用条款与访问频率限制。
- **功能边界**：Cirvel 不绕过 Plex 的账号、授权、Plex Pass 或任何数字版权保护机制，
  需要 Plex Pass 的功能仍按 Plex 的规则提供。
- **Plex 与其它第三方组件**：镜像中的 Plex Media Server 随 LinuxServer 基础镜像一并
  提供，Cirvel 不对其另行授权，使用受 Plex 服务条款约束。基础镜像与 FFmpeg 等组件
  适用各自的许可，见下文。
- **数据**：Cirvel 会把媒体信息写入 Plex 的媒体库数据库。首次部署或升级前，请备份
  `/config`。

## 免责声明

本镜像按「现状」提供。在适用法律允许的最大范围内，开发者不对使用或无法使用本镜像
造成的任何直接或间接后果承担责任，包括但不限于数据丢失、服务中断、存储服务的访问
限制或封禁，以及因媒体内容产生的法律纠纷。你对自己的部署方式、媒体来源及其合规性
负责。

## 第三方组件

镜像中的 `/opt/cirvel/ffmpeg/bin/ffprobe` 由未经修改的 [FFmpeg 6.1.2](https://ffmpeg.org/releases/ffmpeg-6.1.2.tar.xz)
源码构建，按 LGPL-2.1-or-later 发布，构建配置可用它的 `-version` 参数查看。

基础镜像来自 [LinuxServer.io](https://github.com/linuxserver/docker-plex)，其构建脚本按
GPL-3.0 发布，其中的 Plex Media Server 归 Plex, Inc. 所有，见下节。

## 商标与归属

Plex、Plex Media Server 及 Plex 标志是 Plex, Inc. 的商标。Cirvel 是独立的第三方
项目，**与 Plex, Inc. 无任何关联，未获其背书、赞助或认可**。

本镜像基于 [LinuxServer.io](https://docs.linuxserver.io/images/docker-plex/) 的 Plex
镜像构建，其中的 Plex Media Server 由 Plex, Inc. 提供，使用受
[Plex 服务条款](https://www.plex.tv/about/privacy-legal/plex-terms-of-service/) 约束。
是否领取服务器、是否使用 Plex Pass 等均由你与 Plex 之间的关系决定，与本项目无关。
