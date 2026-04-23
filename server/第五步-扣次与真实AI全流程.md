# 第五步：云端扣次数 + 真机走完整「真实 AI」链路

这一步把三件事串成一条线：**服务器扣 `credits`** → **分析前扣次** → **你在真机上从「我的」到「开始排查」走通**。  
**第六步**起，App **不再直连 DeepSeek**，改为 **`POST /v1/hazard/analyze` 由服务端代调模型并扣 1 次**（详见 `第六步-服务端代理DeepSeek.md`）。  
做完后，**还有好多工作**（HTTPS、充值、审核、日志审计等），但 **「能登录、能扣次、能分析」** 的产品主路径就立住了。

---

## 你现在处于哪一步（对照）

| 阶段 | 内容 | 是否必须 |
|------|------|----------|
| ① 宝塔 Node + PM2 | 服务常开 | 已有 |
| ② MySQL + `config.json` | 真实 `users.credits` | 已有 |
| ③ App：内置官方 API + Apple + token | 能 `/v1/me` | 已有 |
| **④ 本步骤** | **`POST /v1/credits/consume` + App 调用** | **本步做** |
| ⑤ 以后 | HTTPS、域名、充值、管理后台、合规文案 | 后续 |

---

## 一、理解规则（1 分钟读完）

- **每次**在 App 里点 **「开始排查」** 且走 **云端真实分析** 时：  
  **第六步之后**由 **`POST /v1/hazard/analyze`** 在服务端 **先扣 1 次再调模型**（仍保留 **`/v1/credits/consume`** 供其它用途或旧客户端）。  
- **本地演示**（未在「我的」填写 API 根地址或未完成 Apple 同步）：**不扣**云端次数。  
- **无网先记录**：**不扣**次数（不调用云端分析）。  
- **重新分析**（记录详情里）：同样会 **先扣 1 次** 再走模型（与「开始排查」一致）。

---

## 二、在 Mac 上准备好新服务端文件

1. 打开你电脑上的项目文件夹里的 **`server/index.js`**（本仓库已更新）。  
2. 确认里面包含 **`POST /v1/credits/consume`**（可全文搜索 `credits/consume`）。若已做第六步，还应存在 **`hazardPrompts.js`** 与 **`POST /v1/hazard/analyze`**。

---

## 三、上传到服务器并重启（宝塔）

1. 宝塔 → **文件** → 进入 **`/www/wwwroot/safemaster-api`**。  
2. 用 **上传 / 覆盖** 把本机最新的 **`index.js`** 传上去（覆盖旧文件）。  
3. 宝塔 → **终端**，执行：

```bash
cd /www/wwwroot/safemaster-api
pm2 restart safemaster-api
```

4. 看到 **`online`** 即成功。

---

## 四、在服务器上用 curl 自测扣次（可选但推荐）

下面命令里的 **`你的TOKEN`** 换成：你先执行 **`POST /v1/auth/apple`** 返回的 **`accessToken`**（一整行复制，勿换行）。

**1）先登录拿 token（示例）**

```bash
curl -s -X POST http://127.0.0.1:3000/v1/auth/apple -H "Content-Type: application/json" -d '{"identityToken":"curl-test-001"}'
```

**2）扣 1 次**

```bash
curl -s -w "\nHTTP:%{http_code}\n" -X POST http://127.0.0.1:3000/v1/credits/consume -H "Content-Type: application/json" -H "Authorization: Bearer 你的TOKEN" -d '{"amount":1}'
```

**成功时**：HTTP 应为 **200**，JSON 里有 **`"ok":true`** 和 **`"credits"`**（比原来少 1）。  
**次数不够时**：HTTP **402**，JSON 里有 **`"error":"次数不足"`** 和当前 **`credits`**。

**3）再查余额**

```bash
curl -s http://127.0.0.1:3000/v1/me -H "Authorization: Bearer 你的TOKEN"
```

---

## 五、在 Mac 上用 Xcode 更新 App

1. 用 **Xcode** 打开工程，**Pull / 保存** 已包含本步改动的 Swift 文件（含 `SafeMasterAPIClient`、`CloudHazardAnalysisService` 等）。  
2. **Product → Clean Build Folder**（建议）。  
3. **真机 Run** 安装。

---

## 六、真机完整走一遍（验收清单）

1. 打开 App → **我的**：  
   - App 已内置官方云端地址（用户不可改）；**Apple 登录** 成功，显示 **已与云端同步**。  
   - **云端剩余分析次数** 有数字（如 5）。  
2. **第六步**：服务器已配置 **`DEEPSEEK_API_KEY`**（或 `config.json` 的 `deepseekApiKey`），App **无需**再放客户端密钥。  
3. 进入 **隐患识别** → 填文字或选照片 → 点 **「开始排查」**。  
4. **预期**：分析正常完成；回到 **我的** 看次数 **减少 1**（或分析过程中界面已刷新）。  
5. 把次数在库里 **手动改成 0**（phpMyAdmin 或 SQL）再试一次 **开始排查**：  
   - **预期**：提示 **次数不足** 类文案，**不会**再调用模型（省你的钱）。

---

## 七、常见问题

**Q：只想本地演示、不想扣次？**  
A：不填「我的」里的 API 根地址或未完成 Apple 登录同步，「开始排查」会走 **Mock 本地演示**，**不会**请求 `/v1/hazard/analyze`，**不扣**云端次数。

**Q：扣次成功但模型报错，算不算白扣？**  
A：当前实现是 **在发起模型请求之前扣次**，因此 **模型失败也会少 1 次**。以后要优化可做「预授权 / 失败回滚」，属于下一阶段。

**Q：演示模式（没接数据库）能扣次吗？**  
A：可以，次数在 **服务器内存** 里模拟，**重启 Node 会重置**。

**Q：后面还有多少事？**  
A：常见还有：**HTTPS + 域名**、**防火墙收紧**、**充值 / 内购**、**管理后台改次数**、**日志与对账**、**隐私政策与审核材料** 等。可以按优先级一项项做。

---

## 八、本步完成标志（你可以打勾）

- [ ] 服务器 `pm2` 已重启且无报错  
- [ ] `curl` 能扣次且 `/v1/me` 数字变化  
- [ ] 真机 **开始排查** 后次数减少  
- [ ] 次数为 0 时被拦截并提示

下一步若要继续做，建议优先：**Nginx + HTTPS**，或 **phpMyAdmin / 简单脚本给用户加次数**（在充值功能上线前手工运维）。
