# Cirvel

让 Plex 原生支持 STRM：**播放由客户端直接连接 CDN 完成，NAS 既不承担上传带宽，也不承担转码开销。**

这是一台普通的 Plex——基于 LinuxServer Plex 镜像，加入 Cirvel 运行时。
客户端、遥控、共享与 plex.tv 的行为都不变。

```sh
docker pull ghcr.io/infinitypacer/cirvel:latest
docker pull infinitypacer/cirvel:latest
```

也可以指定版本：

```sh
docker pull ghcr.io/infinitypacer/cirvel:0.1.0
docker pull infinitypacer/cirvel:0.1.0
```

**本版本内置 Plex Media Server 1.43.4.10903。**

## 它做什么

Plex 原本不认识 `.strm`：要么识别不了媒体信息，要么由服务器下载整个文件再转码
推给客户端——NAS 的上行带宽与 CPU 全部被占住。Cirvel 改变这两件事：

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

## 部署

沿用 LinuxServer Plex 的既有方式即可：同样的 `/config`、同样的 `32400:32400`、
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
保存即生效，无需重启容器；配置随 `/config` 卷持久化。打开该页面需要 Plex
服务器拥有者权限，由 Plex 自身判定。

## 版本与更新

tag 只表示 Cirvel 自己的版本（`0.1.0`、`latest`），与 Plex 的版本号无关。

内置的 Plex 是固定的：每个版本使用一个经过验证的 Plex Media Server，**不随 Plex
的发布自动更新**。升级 Plex 属于 Cirvel 的一次版本变更，会在发布说明里写明
新的 Plex 版本，本页顶部的版本号也会同步。镜像的 `io.infinitypacer.cirvel.plex.version`
标签始终记录当前内置的 Plex 版本，可用 `docker inspect` 查询。

这意味着容器不会自己把 Plex 升上去。想要新的 Plex，拉新版 Cirvel。

## 支持范围

`linux/amd64` 与 `linux/arm64`。源码不在本仓库；这里只做镜像打包与发布。

## 使用须知

- **合法的 Plex 与媒体来源**：Cirvel 只适用于合法安装和使用 Plex Media Server 的用户。
  Cirvel 不提供、不索引、不分发任何影音内容；STRM 指向什么由你决定，你应确保对所
  访问的媒体及其存储服务拥有相应权利，并遵守该存储服务的使用条款与访问频率限制。
- **功能边界**：Cirvel 不绕过 Plex 的账号、授权、Plex Pass 或任何数字版权保护机制，
  需要 Plex Pass 的功能仍按 Plex 的规则提供。
- **Plex 与其它第三方组件**：镜像中的 Plex Media Server 随 LinuxServer 基础镜像一并
  提供，Cirvel 不对其另行授权，使用受 Plex 服务条款约束；基础镜像与 FFmpeg 等组件
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
GPL-3.0 发布；其中的 Plex Media Server 归 Plex, Inc. 所有，见下节。

## 商标与归属

Plex、Plex Media Server 及 Plex 标志是 Plex, Inc. 的商标。Cirvel 是独立的第三方
项目，**与 Plex, Inc. 无任何关联，未获其背书、赞助或认可**。

本镜像基于 [LinuxServer.io](https://docs.linuxserver.io/images/docker-plex/) 的 Plex
镜像构建，其中的 Plex Media Server 由 Plex, Inc. 提供，使用受
[Plex 服务条款](https://www.plex.tv/about/privacy-legal/plex-terms-of-service/) 约束；
是否领取服务器、是否使用 Plex Pass 等均由你与 Plex 之间的关系决定，与本项目无关。
