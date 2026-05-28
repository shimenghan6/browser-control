# browser-control

> AI Agent 浏览器操控统一入口。一个指令打开网页、搜索、点击、填表、截图——卡住了自己换方案，不纠结、不等你问。

**装上之后，跟 Claude Code 说"搜一下 xxx"或"打开 xxx 网站"，它就自动操控浏览器完成。四层备选方案，碰到问题自动切换。**

```
agent-browser (主力) → chrome-devtools-mcp (备选) → nodriver (最后手段)
反爬场景 → CloakBrowser 隐身引擎
```

### 谁需要这个

| 你 | 为什么你需要 |
|----|------------|
| 经常让 Claude Code 搜网页、开网站 | 不用手动指定工具，AI 自己选 |
| 遇到过 agent-browser 卡住不动 | 自动切备选方案，不死磕 |
| 用百度/京东/小红书等国内网站 | 国内大站反爬，自动切隐身引擎 |
| 想一键搞定浏览器+AI 环境 | `install.bat` 双击全装好 |

---

## 为什么需要

单一浏览器工具经常卡壳：
- agent-browser `--headed` 被忽略 → daemon 未重启
- `click @eXX` 返回 Done 但页面没跳转 → headless 模式
- nodriver `uc.start()` 卡住不动 → 浏览器进程冲突
- 弹出验证码 → 被反爬检测

**没有统一策略，Agent 会在同一方案上反复死磕。** 这个 Skill 提供四层备选 + 自愈规则。

## 安装

### 一键安装

```bash
# Linux/macOS
bash install.sh

# Windows
install.bat
```

### 手动安装

```bash
# 1. 安装依赖
npm install -g agent-browser chrome-devtools-mcp
pip install nodriver cloakbrowser

# 2. 配置 agent-browser（推荐）
echo '{ "headed": true }' > ~/agent-browser.json

# 3. 克隆到 Claude Code skills 目录
git clone https://github.com/YOUR_USER/browser-control.git ~/.claude/skills/browser-control
```

### chrome-devtools-mcp 配置（可选）

在 Claude Code 的 MCP 配置中添加：

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest"]
    }
  }
}
```

## 使用

安装后，以下关键词自动触发：

> "打开浏览器"、"搜索xxx"、"打开xxx网站"、"浏览器搜"、"上京东"、"帮我在网上查xxx"

Agent 自动按决策树选择方案，不需要手动指定工具。

## 架构

```
方案一: agent-browser (主力)
  ├─ 启动: close --all → --headed open → snapshot
  ├─ 点击: click @eXX (主) → eval JS (备)
  └─ 翻页: URL参数直接改 (比点"下一页"可靠)

方案二: chrome-devtools-mcp (备选)
  └─ 触发: agent-browser 同一操作失败2次

方案三: nodriver (最后手段)
  └─ 触发: 前两者均失败

反爬场景: CloakBrowser 隐身引擎
  └─ 触发: 遇到验证码/反Bot检测
```

## 工具对照

| 操作 | agent-browser | chrome-devtools-mcp | nodriver |
|------|-------------|-------------------|----------|
| 打开页面 | `open "URL"` | `navigate_page` | `browser.get()` |
| 获取结构 | `snapshot -i` | `take_snapshot` | `query_selector_all` |
| 点击元素 | `click @eN` | `click` | `item.click()` |
| 执行JS | `eval "..."` | `evaluate_script` | `page.evaluate()` |
| 截图 | `screenshot` | `take_screenshot` | — |
| 性能分析 | — | `performance_start_trace` | — |
| 网络监控 | — | `list_network_requests` | — |

## 关键经验

### agent-browser

- 启动前必须 `close --all`，否则 `--headed` 被忽略
- `click @eXX` 在 headless 模式下经常失效 → 立刻换 `eval "document.querySelectorAll('...')[N].click()"`
- 百度翻页直接改 URL（`&pn=10`），比点击"下一页"可靠得多

### chrome-devtools-mcp

- Google 官方 MCP 服务器，稳定性和兼容性最好
- 支持性能分析和网络监控，agent-browser 没有的能力

### nodriver

- 启动浏览器经常卡死 → 只当最后保底
- 速度慢，不适合频繁翻页

### CloakBrowser

- C++ 源码级反检测 Chromium，30/30 检测全过
- reCAPTCHA v3 评分 0.9（人类级别）

## 故障排查

| 问题 | 解决 |
|------|------|
| `--headed ignored` | `agent-browser close --all` 后重试 |
| click 返回 Done 但没跳转 | 换 `eval "document.querySelectorAll('h3 a')[N].click()"` |
| 同一方案失败2次 | 强制切换下一层方案 |
| 验证码/反爬 | 切 CloakBrowser |
| nodriver 卡住 | 放弃，切回 agent-browser eval |
| 翻页没反应 | 直接 URL 加 `&pn=10` |

## 方案切换决策树

```
开始 → agent-browser --headed
         │
         ├─ OK → 继续
         └─ 失败×2 → chrome-devtools-mcp
                       │
                       ├─ OK → 继续
                       └─ 失败 → nodriver
                                  │
                                  ├─ OK → 继续
                                  └─ 失败/卡30s → 放弃
```

## License

MIT
