# Clear

Clear 是一个本地优先、可解释、可撤销的 macOS 内存健康与安全清理工具。

它不会伪装成“清空 RAM”按钮。Clear 关注真实的内存压力、压缩内存和交换空间，并帮助用户安全退出高占用应用。磁盘清理只识别严格白名单中的可再生缓存和旧日志，执行前始终预览，默认移动到废纸篓。

## 当前实现

- macOS 14+
- Swift 6 / SwiftUI
- `arm64 + x86_64` Universal Binary
- 内存压力与系统内存采样
- 高占用 GUI 应用排行与正常退出请求
- 安全的只读缓存/旧日志扫描
- 候选项预览、选择和移入废纸篓
- 路径边界、符号链接和文件替换复验
- Apple Silicon 与 Intel GitHub Actions 测试

MVP 不请求 Full Disk Access，不安装 root Helper，不扫描 Mail、Messages、Safari、Application Support、Containers、其他用户或系统卷。

## 开发

在 macOS 14 或更高版本安装 Xcode 后：

```bash
swift test
swift run Clear
```

也可以直接在 Xcode 中打开 `Package.swift`，选择 `Clear` scheme 运行。

构建 Universal App：

```bash
bash scripts/build_universal_app.sh
```

生成 DMG 和 SHA-256：

```bash
CLEAR_VERSION=0.1.0 bash scripts/package_dmg.sh
```

## 安装未认证版本

项目当前不使用 Developer ID 证书，也不提交 Apple 公证。GitHub Releases 中的 App 只有不带身份的 ad-hoc 完整性签名。

下载后首次启动如果被 macOS 阻止：

1. 尝试打开一次 Clear。
2. 打开“系统设置 → 隐私与安全性”。
3. 在安全区域找到 Clear，选择“仍要打开”。
4. 核对 Release 页面公布的 SHA-256。

不要关闭 Gatekeeper 或 SIP，也不要批量移除 quarantine 属性。每次更新都可能需要重新信任，并重新授予目录访问权限。

## 安全原则

- 扫描永远先只读。
- 未识别内容永远不会自动进入清理候选。
- 清理计划创建后不可变，执行前逐项重新验证。
- 首版只处理满足年龄规则的普通叶子文件，不把整个目录作为候选。
- 最终移动使用 `openat`/`fstatat` 锚定可信根目录，不跟随祖先符号链接。
- 默认使用系统废纸篓，不提供自动永久删除。
- 无法确认就拒绝操作，并把原因展示给用户。

## License

[MIT](LICENSE)
