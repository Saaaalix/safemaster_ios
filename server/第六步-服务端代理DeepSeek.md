# 第六步：服务端代理 DeepSeek（密钥不出 App）

## 目标

- DeepSeek API Key **只放在服务器**（环境变量或 `config.json`），**不要**再写入 Xcode 工程。
- App 在「我的」填写你的 API 根地址并完成 Apple 登录后，「开始排查」会请求 **`POST /v1/hazard/analyze`**：服务端先 **扣 1 次**，再代调 DeepSeek，返回与原先一致的 JSON 分析字段。

## 1. 上传/覆盖文件

在宝塔（或 SSH）进入与 `index.js` 相同的目录，确保存在：

- `index.js`（含 `/v1/hazard/analyze`）
- `hazardPrompts.js`（与 `index.js` 同目录，`require("./hazardPrompts")` 才能加载）
- （可选）`verify-remote-env.sh`：上传后在同目录 `chmod +x verify-remote-env.sh && ./verify-remote-env.sh`，把输出贴给 Cursor 排错。

本地仓库中请维护 **`docs/SERVER_ENV.md`**（路径、PM2 名、端口等），避免每次对话重复口述宝塔环境。

## 2. 配置密钥（二选一或同时存在，优先级见下）

**推荐：** 在 PM2 ecosystem 或系统环境中设置（**勿**把真密钥写进 Git 或聊天）：

```bash
export DEEPSEEK_API_KEY="你的密钥"
```

**或** 在已有 `config.json` 中增加字段（与数据库配置同文件时注意不要泄露备份）：

```json
"deepseekApiKey": "你的密钥"
```

**优先级：** 环境变量 `DEEPSEEK_API_KEY` **优先于** `config.json` 中的 `deepseekApiKey`。

可参考仓库内 `server/config.example.json`（示例勿填真密钥）。

## 3. 重启服务

```bash
cd /你的项目目录/server
pm2 restart safemaster-api
# 或你实际使用的进程名
pm2 logs safemaster-api --lines 80
```

## 4. 自检

```bash
curl -sS http://127.0.0.1:3000/health
```

未配置密钥时，带 Bearer 调用分析接口应返回 **503** 且文案提示配置 DeepSeek；配置并重启后应返回 **200** 且含 `analysis`（需先有次数，见第五步）。

## 5. App 侧

- 更新到本步对应的 Swift 工程后：**删除** 本地的 `DeepSeekSecrets.swift`（若曾含密钥，请到 DeepSeek 控制台**轮换新密钥**）。
- 在「我的」填写 API 根地址（如 `https://你的域名`），Apple 登录同步成功后即可走云端分析。

## 6. 常见问题

**Q：提示 503「服务器未配置 DeepSeek」**  
A：检查环境变量或 `config.json` 是否生效，并确认已 `pm2 restart`。

**Q：仍想本地演示不扣次**  
A：不填 API 地址或未完成 Apple 同步时，App 使用本地 Mock，不会请求 `/v1/hazard/analyze`。
