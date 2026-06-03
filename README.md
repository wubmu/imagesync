# imagesync

基于 GitHub Actions 的 Docker 镜像同步工具，自动将海外镜像同步到国内镜像仓库。

## 工作原理

```
┌─────────────────────────────────────────────────────────────────────┐
│                        imagesync 工作流程                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  触发方式（二选一）                                                   │
│  ┌──────────────────────┐    ┌──────────────────────┐               │
│  │  cron 定时触发        │    │  push 到 main 分支    │               │
│  │  每3小时自动运行      │    │  紧急同步时手动推送    │               │
│  └──────────┬───────────┘    └──────────┬───────────┘               │
│             │                           │                           │
│             ▼                           ▼                           │
│  ┌──────────────────────┐    ┌──────────────────────┐               │
│  │  script.sh            │    │  直接指定配置文件     │               │
│  │  哈希取模选出本轮文件  │    │  (如 conf/redis.yaml) │               │
│  └──────────┬───────────┘    └──────────┬───────────┘               │
│             │                           │                           │
│             ▼                           ▼                           │
│  ┌──────────────────────────────────────────────────────┐           │
│  │              GitHub Actions 并行执行                   │           │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐              │           │
│  │  │conf/a   │  │conf/b   │  │conf/c   │  ...         │           │
│  │  └────┬────┘  └────┬────┘  └────┬────┘              │           │
│  └───────┼─────────────┼─────────────┼──────────────────┘           │
│          │             │             │                              │
│          ▼             ▼             ▼                              │
│  ┌──────────────────────────────────────────────────────┐           │
│  │  从 IMAGESYNC_AUTH_CONFIG Secret 读取仓库认证信息      │           │
│  │              逐个拉取源镜像 → 推送到目标仓库             │           │
│  └──────────────────────────────────────────────────────┘           │
│          │             │             │                              │
│          ▼             ▼             ▼                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                         │
│  │阿里云 ACR │  │腾讯云 TCR │  │  ...     │                         │
│  └──────────┘  └──────────┘  └──────────┘                         │
│                                                                     │
│  最终效果：                                                          │
│  docker pull registry.cn-guangzhou.aliyuncs.com/ypub/nginx         │
│  （国内直接拉取，无需翻墙，速度快）                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

- **定时调度**：每 3 小时触发，通过哈希取模将 `conf/` 下的文件分散到不同时段，避免一次性处理全部镜像导致超时
- **推送触发**：push 到 main 分支时同步指定配置文件，适合紧急更新
- **认证安全**：凭据通过 GitHub Secret 管理，不提交到代码中

## 项目结构

```
├── .github/workflows/
│   ├── image-mirror-schedule.yaml   # 定时同步（cron + 手动触发）
│   └── image-mirror-push.yaml       # push 到 main 时同步
├── conf/                            # 镜像配置文件（按分类）
├── auth.yaml                        # 认证信息（⚠️ 不提交，通过 Secret 管理）
├── script.sh                        # 哈希取模调度脚本
└── Makefile                         # 快捷命令
```

## 快速开始

### 1. 配置认证信息

首先，在目标镜像仓库中创建命名空间，获取用户名和密码：

- **阿里云 ACR**：https://cr.console.aliyun.com/cn-guangzhou/instances
- **腾讯云 TCR**：https://console.cloud.tencent.com/tcr

然后在 GitHub 仓库中配置 Secret：

1. 打开仓库 **Settings → Secrets and variables → Actions**
2. 点击 **New repository secret**
3. Name 填：`IMAGESYNC_AUTH_CONFIG`
4. Value 填 `auth.yaml` 的有效内容（去掉注释），格式如下：

```yaml
ccr.ccs.tencentyun.com:
  username: 你的用户名
  password: 你的密码

registry.cn-guangzhou.aliyuncs.com:
  username: 你的用户名
  password: 你的密码
```

5. 点击 **Add secret** 保存

### 2. 添加镜像配置

在 `conf/` 目录下添加 yaml 文件：

```yaml
# 格式：源镜像地址:tag1,tag2,tag3:
#   缩进 - 目标镜像地址

# 同步多个 tag
docker.io/nginx:latest,stable,alpine:
- registry.cn-guangzhou.aliyuncs.com/your-ns/nginx

# 同步特定版本
docker.io/postgres:16-alpine:
- registry.cn-guangzhou.aliyuncs.com/your-ns/postgres

# 同步到多个目标仓库
docker.io/redis:latest,7:
- registry.cn-guangzhou.aliyuncs.com/your-ns/redis
- ccr.ccs.tencentyun.com/your-ns/redis
```

### 3. 调整调度频率

编辑 `.github/workflows/image-mirror-schedule.yaml`，修改 cron 和 `SYNC_MOD` 环境变量：

```yaml
schedule:
- cron: '15 */3 * * *'  # 每3小时触发

env:
  SYNC_MOD: 8           # 配合 cron：每1h→24, 每2h→12, 每3h→8, 每4h→6, 每6h→4
```

| cron 频率 | SYNC_MOD | 每次处理的配置占比 |
|-----------|----------|------------------|
| 每 1 小时 | `24` | 1/24 |
| 每 2 小时 | `12` | 1/12 |
| 每 3 小时 | `8` | 1/8 |
| 每 4 小时 | `6` | 1/6 |
| 每 6 小时 | `4` | 1/4 |

### 4. 提交并等待

```bash
make    # git add . && git commit -m "update" && git push
```

## 给朋友：如何使用这个项目

```
┌─────────────────────────────────────────────────────┐
│                    使用流程                           │
│                                                     │
│  1. Fork 本仓库到你的 GitHub 账号                     │
│     │                                               │
│     ▼                                               │
│  2. 启用 Actions（GitHub 默认禁用 Fork 的定时任务）   │
│     进入 Actions 页面，点击启用按钮                    │
│     │                                               │
│     ▼                                               │
│  3. 设置 Secret                                      │
│     Settings → Secrets → New secret                 │
│     Name:  IMAGESYNC_AUTH_CONFIG                    │
│     Value: 你的镜像仓库认证 yaml                      │
│     │                                               │
│     ▼                                               │
│  4. 修改 conf/ 配置                                  │
│     把目标地址换成你的命名空间                         │
│     如 ypub → your-ns                               │
│     │                                               │
│     ▼                                               │
│  5. 推送代码                                         │
│     git push                                        │
│     │                                               │
│     ▼                                               │
│  6. Actions 自动运行，镜像同步完成                    │
│     docker pull 你的仓库地址/nginx:latest            │
│                                                     │
└─────────────────────────────────────────────────────┘
```

1. **Fork 本仓库**到你自己的 GitHub 账号
2. 在你 Fork 的仓库中，进入 **Actions** 页面，点击 **"I understand my workflows, go ahead and enable them"** 启用工作流（GitHub 默认会禁用 Fork 仓库的定时任务）
3. 在 Fork 的仓库中设置 `IMAGESYNC_AUTH_CONFIG` Secret（填你自己的镜像仓库认证），**未配置 Secret 会导致工作流失败**
4. 修改 `conf/` 下的配置文件，把目标仓库地址换成你自己的命名空间
5. 按需调整 cron 频率和 mod 值
6. 推送后 Actions 自动运行

## 依赖

- [hhyasdf/image-sync-action](https://github.com/hhyasdf/image-sync-action) - 核心镜像同步 Action

## License

MIT
