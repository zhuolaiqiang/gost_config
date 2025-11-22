# gost_config

集中管理 GOST（Go Simple Tunnel）部署脚本与配置示例，已适配在 Debian 系统上以 systemd 后台运行。项目采用 CLI 方式启动，不依赖 v3 配置文件格式，减少环境差异影响。

## 快速使用

1. 编译并安装 GOST 二进制

- `git clone https://github.com/go-gost/gost.git`
- `cd gost/cmd/gost`
- `go build`
- `sudo install -m 0755 ./gost /usr/local/bin/gost`

2. 一次性 CLI 验证

- `sudo /usr/local/bin/gost -L tcp://:443/158.51.110.124:9000 -L udp://:443/158.51.110.124:9000?ttl=300`

3. systemd 后台部署

- 在仓库根目录执行：`bash scripts/deploy_gost_systemd.sh`
- 脚本行为：
  - 创建日志目录与文件：`/var/log/gost/gost.log`
  - 如存在 `gost_config.json` 且包含 `ServeNodes`，自动转换为 `-L` 参数；否则使用内置默认
  - 写入并启用 `gost.service`，以 CLI 模式启动，日志只记录 `error` 级别到文件

4. 常用运维命令

- `sudo systemctl status gost --no-pager -n 0`
- `sudo systemctl restart gost`
- `sudo systemctl stop gost`
- `sudo journalctl -u gost --no-pager -n 100`
- `sudo tail -n 100 /var/log/gost/gost.log`

## 修改转发

- 编辑仓库根目录的 `gost_config.json` 中的 `ServeNodes` 列表（示例）：

```json
{
  "ServeNodes": [
    "tcp://:443/158.51.110.124:9000",
    "udp://:443/158.51.110.124:9000?ttl=300"
  ]
}
```

- 重新执行脚本或重启服务：`sudo systemctl restart gost`

## 源码编译加速（可选）

- 设置 Go 模块代理：`go env -w GOPROXY=https://goproxy.cn,direct`
- 预下载依赖：`go mod download -x`
- 遇到校验受限时临时关闭：`go env -w GOSUMDB=off`（完成后建议恢复）

## 项目结构

- `gost_config.json`：可选，包含 `ServeNodes` 时自动生成 `-L` 启动参数
- `scripts/deploy_gost_systemd.sh`：部署脚本，生成并启动 `gost.service`
- `README.md`：使用说明

## 注意事项

- 生产环境避免在仓库中提交敏感信息；目标地址建议通过环境变量或外部注入方式维护
- 若端口或目标地址变更，需同步更新 `ServeNodes` 或手动修改 `gost.service`
