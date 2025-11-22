# gost_config

用于管理和版本化 GOST（Go Simple Tunnel）相关的配置与脚本，便于在不同环境下统一维护、审阅与发布。

## 快速上手

本地初始化并推送到 GitHub：

```bash
git init
git add README.md
git commit -m "chore: add README"
git branch -M main
git remote add origin git@github.com:zhuolaiqiang/gost_config.git
git push -u origin main
```

如远端仓库尚未创建，请先在 GitHub 上新建同名仓库并选用空白初始化。

## 目录建议

- `configs/` 存放 GOST 配置文件（如 `json`/`yaml`），按环境或节点分目录
- `scripts/` 常用启动、重载、健康检查等脚本
- `examples/` 示例配置与参考模板
- `docs/` 额外说明与操作手册（可选）

以上为建议结构，仅在需要时逐步补充，不必一次性创建全部目录。

## 配置约定

- 按环境命名目录与文件，如 `configs/prod/`, `configs/staging/`
- 使用清晰的命名区分不同节点或传输协议
- 提交前确保敏感信息以环境变量或占位符方式处理

## 协作流程

- 使用 `main` 作为稳定分支，变更在 `feature/*` 分支进行
- 提交信息简洁明确，包含变更范围与影响
- 通过合并请求进行审阅，确保配置在目标环境可用

## 后续规划

- 增加常用配置模板与脚本
- 引入简单校验与启动检查流程