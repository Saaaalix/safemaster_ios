# 服务端法规库目录

该目录用于放置云端法规库文件，`/v1/hazard/analyze` 会在服务端本地读取并参与检索。

支持以下任一文件形态：

- `laws_basis.jsonl` 或 `laws_basis.jsonl.gz`
- `laws_playbook.jsonl` 或 `laws_playbook.jsonl.gz`

优先读取 `.jsonl`，不存在时读取 `.jsonl.gz`。

可通过以下方式自定义目录：

- `config.json` 中设置 `lawsDir`
- 或环境变量 `LAWS_DIR`

验证加载状态：

```bash
curl http://127.0.0.1:3000/v1/laws/status
```
