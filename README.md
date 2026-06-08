# imagesync

基于 GitHub Actions 的 Docker 镜像同步工具，自动将海外镜像同步到国内镜像仓库。

## 工作原理

```
┌─────────────────────────────────────────────────────────────────────┐
│                        imagesync 工作流程                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  触发方式（三选一）                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐   │
│  │  cron 定时触发    │  │  push 到 main    │  │  workflow_dispatch│  │
│  │  每6小时自动运行  │  │  紧急同步时推送    │  │  Actions 页面手动  │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘   │
│           │                     │                     │             │
│           ▼                     ▼                     ▼             │
│  ┌──────────────────┐  ┌──────────────────┐                         │
│  │  script.sh        │  │  指定配置文件     │                         │
│  │  哈希取模选出本轮  │  │  (matrix 列表)   │                         │
│  └────────┬─────────┘  └────────┬─────────┘                         │
│           │                     │                                   │
│           ▼                     ▼                                   │
│  ┌──────────────────────────────────────────────────────┐           │
│  │  envsubst 替换 ${TARGET_REGISTRY} → 实际仓库地址      │           │
│  └──────────────────────────┬───────────────────────────┘           │
│                             │                                       │
│                             ▼                                       │
│  ┌──────────────────────────────────────────────────────┐           │
│  │  image-sync-action 并行同步                           │           │
│  │  从源拉取 → 推送到目标仓库（proc: 20 并发）             │           │
│  └──────────────────────────────────────────────────────┘           │
│                                                                     │
│  最终效果：                                                          │
│  docker pull registry.cn-guangzhou.aliyuncs.com/ypub/nginx         │
│  （国内直接拉取，无需翻墙，速度快）                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

- **定时调度**：通过 MD5 哈希取模将 `conf/` 下的文件分散到不同轮次，避免一次性处理全部镜像导致超时。支持 1~7 天的调度周期
- **推送触发**：push 到 main 分支时同步指定配置文件，适合紧急更新
- **手动触发**：Actions 页面 → `image-mirror-schedule` → Run workflow
- **认证安全**：凭据通过 GitHub Secret 管理，不提交到代码中
- **地址参数化**：目标 registry 通过 `TARGET_REGISTRY` 环境变量统一管理，fork 后改一处即可

## 项目结构

```
.
├── .github/workflows/
│   ├── image-mirror-schedule.yaml   # 定时同步（cron + 手动触发）
│   └── image-mirror-push.yaml       # push 到 main 时同步
├── conf/                            # 镜像配置文件（按分类）
│   ├── nginx.yaml                   # 每个文件对应一组镜像
│   ├── redis.yaml
│   ├── homelab.yaml                 # homelab 专属镜像
│   └── ...
├── unuse/                           # 冷备归档（不参与同步，需要时移回 conf/）
├── script.sh                        # 哈希取模调度脚本
└── Makefile                         # 快捷命令
```

## 快速开始

### 1. Fork 并启用 Actions

1. Fork 本仓库到你自己的 GitHub 账号
2. 进入你 Fork 的仓库，打开 **Actions** 页面
3. 点击 **"I understand my workflows, go ahead and enable them"** 启用工作流（GitHub 默认会禁用 Fork 仓库的定时任务）

### 2. 修改目标 Registry 地址

编辑 `.github/workflows/image-mirror-schedule.yaml` 和 `image-mirror-push.yaml`，修改顶部的 `TARGET_REGISTRY`：

```yaml
env:
  TARGET_REGISTRY: registry.cn-guangzhou.aliyuncs.com/your-namespace
```

> 只需改这一个值，所有 `conf/*.yaml` 中的目标地址会自动使用这个前缀，无需逐个修改配置文件。

### 3. 配置镜像仓库认证

在目标镜像仓库中创建命名空间，获取用户名和密码：

- **阿里云 ACR**：https://cr.console.aliyun.com/cn-guangzhou/instances
- **腾讯云 TCR**：https://console.cloud.tencent.com/tcr

然后在 GitHub 仓库中配置 Secret：

1. 打开仓库 **Settings → Secrets and variables → Actions**
2. 点击 **New repository secret**
3. **Name** 填：`IMAGESYNC_AUTH_CONFIG`
4. **Value** 填以下格式的 YAML：

```yaml
registry.cn-guangzhou.aliyuncs.com:
  username: 你的用户名
  password: 你的密码

ccr.ccs.tencentyun.com:
  username: 你的用户名
  password: 你的密码
```

5. 点击 **Add secret** 保存

> ⚠️ **Secret Name 必须是 `IMAGESYNC_AUTH_CONFIG`**，工作流依赖此名称。未配置会导致工作流失败。

### 4. 添加/修改镜像配置

在 `conf/` 目录下添加或修改 yaml 文件：

```yaml
# 格式：源镜像地址:tag1,tag2:
#   缩进 - ${TARGET_REGISTRY}/镜像名

# 同步多个 tag
docker.io/nginx:latest,stable,alpine:
- ${TARGET_REGISTRY}/nginx

# 同步特定版本
docker.io/postgres:16-alpine:
- ${TARGET_REGISTRY}/postgres

# 同步到多个目标仓库
docker.io/redis:latest,7:
- ${TARGET_REGISTRY}/redis
- ccr.ccs.tencentyun.com/your-ns/redis
```

> 目标地址使用 `${TARGET_REGISTRY}` 占位符，运行时会自动替换为 workflow 中配置的实际值。

### 5. （可选）调整调度频率

编辑 `.github/workflows/image-mirror-schedule.yaml` 中的 cron 和调度参数：

```yaml
schedule:
- cron: '0 */6 * * *'       # cron 触发间隔

env:
  TARGET_REGISTRY: registry.cn-guangzhou.aliyuncs.com/ypub
  SYNC_MOD: 28              # 取模值 = 周期天数 × 24 ÷ 间隔小时数
  SYNC_INTERVAL_HOURS: 6    # 与 cron 间隔保持一致（小时）
```

| 周期 | cron 频率 | SYNC_INTERVAL_HOURS | SYNC_MOD |
| ---- | --------- | ------------------- | -------- |
| 1 天 | 每 3h     | 3                   | 8        |
| 1 天 | 每 6h     | 6                   | 4        |
| 3 天 | 每 6h     | 6                   | 12       |
| 7 天 | 每 6h     | 6                   | 28       |
| 7 天 | 每 8h     | 8                   | 21       |

每个 `conf/*.yaml` 文件通过 MD5 哈希被分配到某个 bucket，经过 SYNC_MOD 轮次后所有文件恰好被处理一次。

### 6. 提交并运行

```bash
make    # git add . && git commit -m "update" && git push
```

推送后 Actions 自动运行。也可以在 Actions 页面手动触发 `image-mirror-schedule` → Run workflow 立即测试。

## 如何运行

### 自动运行

推送代码到 main 分支后，GitHub Actions 自动按 cron 表达式定时执行。当前配置：**每 6 小时一次，7 天为一个完整周期**。

### 手动触发

1. 进入 GitHub 仓库的 **Actions** 页面
2. 左侧选择 **image-mirror-schedule**
3. 点击 **Run workflow** → 绿色 **Run workflow** 按钮
4. 等待 job 完成（约 5-15 分钟）

### 手动指定文件同步（紧急更新）

1. 编辑 `.github/workflows/image-mirror-push.yaml`，修改 `matrix.images_file` 列表：

```yaml
strategy:
  matrix:
    images_file:
    - ./conf/redis.yaml
    - ./conf/nginx.yaml    # 添加你要同步的文件
```

2. 提交并推送到 main 分支，触发 `image-mirror-push` 工作流

### 冷备归档

`unuse/` 目录存放暂时不用的镜像配置，不会参与同步。需要恢复时直接移回 `conf/`：

```bash
mv unuse/alist.yaml conf/
```

## 镜像配置文件列表

| 文件 | 内容 |
|------|------|
| alpine.yaml | Alpine Linux |
| ubuntu.yaml | Ubuntu |
| debian.yaml | Debian |
| golang.yaml | Go |
| node.yaml | Node.js |
| python.yaml | Python |
| java_images.yaml | Amazon Corretto JDK |
| redis.yaml | Redis + RedisInsight |
| mongo.yaml | MongoDB |
| official_images.yaml | PostgreSQL, MySQL, MariaDB |
| nginx.yaml | Nginx + Nginx Proxy Manager |
| traefik.yaml | Traefik |
| frp.yaml | FRP 内网穿透 |
| certbot.yaml | Certbot |
| docker_images.yaml | Docker + DinD |
| dind_images.yaml | Ubuntu DinD |
| ghcr_images.yaml | Immich, Homepage, Coder |
| grafana.yaml | Grafana |
| headscale.yaml | Tailscale, Headscale |
| authentik.yaml | Authentik |
| gitea_images.yaml | Gitea + Runner |
| minio.yaml | MinIO |
| nextcloud.yaml | Nextcloud |
| onedrive.yaml | OneDrive |
| rsshub.yaml | RSSHub |
| wewerss.yaml | WeWe RSS |
| cerebro.yaml | Cerebro, Kafka UI |
| other_images.yaml | Vaultwarden, Memos, Alist, Syncthing 等 |
| k3s.yaml | K3s 相关镜像 |
| devcontainers_images.yaml | VS Code Dev Containers |
| homelab.yaml | Homelab 专属（ES, Kafka, ClickHouse, n8n 等） |

## 依赖

- [hhyasdf/image-sync-action](https://github.com/hhyasdf/image-sync-action) - 核心镜像同步 Action

## License

MIT
