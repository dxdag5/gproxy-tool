# 密钥文件目录

将你的 VPS 私钥文件（`.pem`、`id_rsa` 等）放在此目录下，GProxy 会自动发现并使用。

**注意**：私钥文件不会被提交到 Git 仓库（已在 `.gitignore` 中排除）。

## 示例

```bash
# 复制你的私钥到此目录
cp ~/.ssh/my_vps_key.pem config/

# 或者直接创建软链接
ln -s ~/.ssh/id_rsa config/id_rsa
```
