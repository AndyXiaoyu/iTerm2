# iTerm2 汉化术语规范（强制遵守）

统一采用 **Apple macOS 官方简体中文术语**，与系统其他 App 一致。

## 核心术语对照
| 英文 | 中文（必须用） |
|---|---|
| Copy | 拷贝 |
| Paste | 粘贴 |
| Cut | 剪切 |
| Save | 存储 |
| Save As | 存储为 |
| Open | 打开 |
| Close | 关闭 |
| Quit | 退出 |
| Preferences / Settings | 偏好设置 |
| Profile / Profiles | 配置文件 |
| Window | 窗口 |
| Tab | 标签页 |
| Session | 会话 |
| Pane | 分隔窗格 |
| Edit | 编辑 |
| View | 显示 |
| Find | 查找 |
| Replace | 替换 |
| Select All | 全选 |
| Undo / Redo | 撤销 / 重做 |
| Minimize | 最小化 |
| Zoom | 缩放 |
| Bring All to Front | 全部移至最前 |
| Default | 默认 |
| Enable / Disable | 启用 / 停用 |
| Advanced | 高级 |
| General | 通用 |
| Appearance | 外观 |
| Keys | 按键 |
| Hotkey | 热键 |
| Shortcut | 快捷键 |
| Cancel | 取消 |
| OK | 好 |
| Apply | 应用 |
| Remove / Delete | 移除 / 删除 |
| Add | 添加 |
| Reset | 重置 |
| Import / Export | 导入 / 导出 |
| Browser | 浏览器 |
| Clipboard | 剪贴板 |
| Selection | 所选内容 |
| Scrollback | 回滚 |
| Buffer | 缓冲区 |
| Trigger | 触发器 |
| Snippet | 片段 |
| Badge | 标记 |
| Status Bar | 状态栏 |
| Password Manager | 密码管理器 |

## 翻译规则
1. **只翻译 `"key" = "值";` 中等号右边的值**，key（含 ObjectID）和注释行原样保留。
2. 保留首行的 BOM 和空行结构。
3. 占位符 `%@`、`%d`、`%1$@`、`\n`、`\"` 等**原样保留**，不翻译、不增删。
4. 含 HTML 标签（`<a href=...>`）的，只翻译可见文字，标签和链接保留。
5. 纯符号、数字、单字母、`iTerm2`/`tmux`/`SSH`/`Python` 等专有名词**保持原样**。
6. 菜单项的省略号 `...` 统一用中文省略号 `…`（macOS 规范）。
7. 已是中文或无需翻译的，保持不变。
8. 翻译要简洁、符合 macOS 界面习惯，不啰嗦。
