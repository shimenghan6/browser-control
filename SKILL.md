---
name: browser-control
description: |
  浏览器操控统一入口。自动选择最佳方案：agent-browser CLI为主，eval JS为点击备选，chrome-devtools-mcp为备选，nodriver为最后手段。支持CloakBrowser隐身引擎。
  触发条件："打开浏览器", "搜索xxx", "搜一下xxx", "打开xxx网站", "浏览器搜",
  "帮我在网上查xxx", "用百度搜索", "上京东", any browser/search request.
---

# 浏览器操控技能 - 四层架构

agent-browser(主力) → chrome-devtools-mcp(备选) → nodriver(最后手段)
反爬场景：CloakBrowser隐身引擎

## 核心原则

1. **一次到位**：直接选对工具和页面，不要反复切换尝试
2. **不阻塞**：脚本不加 `input()` 等交互，执行完保持浏览器窗口让用户看到
3. **用户可见**：agent-browser 永远加 `--headed`
4. **卡住自愈**：同一方案卡住2次立刻换方案，不等用户问，不反复死磕

## 自动路由规则

| 网站类型 | 例子 | 控制层 |
|------|------|------|
| 国内大站（反爬） | 百度、京东、小红书、淘宝 | agent-browser / CloakBrowser |
| 普通网站 | GitHub、MDN、Stack Overflow | agent-browser |
| agent-browser卡住2次 | — | chrome-devtools-mcp（备选） |
| 前两者均失败 | — | nodriver（最后手段） |

---

## 方案一：agent-browser（首选，所有网站）

### 启动（每次任务前必须做）

```bash
agent-browser close --all 2>/dev/null; sleep 1
agent-browser --headed open "URL"
agent-browser wait --load networkidle
```

### 获取页面结构

```bash
agent-browser snapshot -i        # 获取所有元素ref
```

### 点击链接 — 主方案 + 备选方案

**主方案：ref点击**
```bash
agent-browser click @eXX        # XX是snapshot中的ref编号
```

**备选方案：JS eval点击（主方案失效时立即切换，不纠结）**
```bash
# 按索引点击第N个h3链接（0-indexed）
agent-browser eval "document.querySelectorAll('h3 a')[N].click()"

# 验证是否跳转成功
agent-browser eval "document.title"
```

### 翻页

```bash
# 百度翻页：直接改URL比点击"下一页"更可靠
# 第1页: https://www.baidu.com/s?wd=关键词
# 第2页: https://www.baidu.com/s?wd=关键词&pn=10
# 第3页: https://www.baidu.com/s?wd=关键词&pn=20
```

### 百度搜索模板

```bash
agent-browser open "https://www.baidu.com/s?wd=关键词"
agent-browser open "https://www.baidu.com/s?wd=关键词&pn=10"  # 第2页
```

---

## 方案二：chrome-devtools-mcp（备选控制层）

**触发条件：agent-browser同一操作连续失败2次时，立即切换到此方案。**

chrome-devtools-mcp 是 Google 官方的 MCP 服务器，暴露 Chrome DevTools 全能力给 AI Agent。

### 核心工具对照

| MCP Tool | 对应 agent-browser |
|------|------|
| `mcp__chrome-devtools__navigate_page` | agent-browser open |
| `mcp__chrome-devtools__take_snapshot` | agent-browser snapshot |
| `mcp__chrome-devtools__click` | agent-browser click |
| `mcp__chrome-devtools__fill` | agent-browser fill |
| `mcp__chrome-devtools__evaluate_script` | agent-browser eval |
| `mcp__chrome-devtools__take_screenshot` | agent-browser screenshot |
| `mcp__chrome-devtools__performance_start_trace` | 无（专有能力） |
| `mcp__chrome-devtools__list_network_requests` | 无（专有能力） |

---

## 方案三：nodriver（最后手段，仅前两者都失败时使用）

**注意：nodriver启动浏览器经常卡死（`uc.start()` 无响应）。卡住超过30秒立刻放弃。**

```python
import asyncio, nodriver as uc

async def main():
    browser = await uc.start()  # 自动检测浏览器
    page = await browser.get('https://www.baidu.com/s?wd=关键词')
    await page.sleep(3)

    items = await page.query_selector_all('h3 a')
    for item in items:
        text = (item.text or '').strip()
        if text and '广告' not in text:
            print(f'点击: {text}')
            await item.click()
            break

    await page.sleep(5)
    await asyncio.Event().wait()

asyncio.run(main())
```

---

## CloakBrowser 隐身引擎

**触发条件：目标网站有反爬/反Bot检测（百度验证码、Cloudflare Turnstile、京东盾等）。**

CloakBrowser 是 C++ 源码级反检测 Chromium（基于 Chromium 146）。
30/30 检测全过，reCAPTCHA v3 评分 0.9（人类级别）。
Playwright 即插即用替代，仅需改一行导入：

```python
import cloakbrowser
browser = cloakbrowser.launch(headless=False)
```

---

## 故障排查清单

| 问题 | 原因 | 解决 |
|------|------|------|
| `--headed ignored` 警告 | daemon已在运行 | `agent-browser close --all` 后重试 |
| click @eXX 返回Done但页面没跳转 | daemon headless模式 | 改用 `agent-browser eval "document.querySelectorAll('h3 a')[N].click()"` |
| 同一方案连续失败2次 | 当前方案不适用 | **切换方案二 chrome-devtools-mcp** |
| chrome-devtools-mcp也无法完成 | 网站兼容性问题 | 切方案三 nodriver（最后保底） |
| 遇到验证码/反爬拦截 | 被Bot检测到 | 切 CloakBrowser 隐身引擎 |
| nodriver `uc.start()` 卡住 | 浏览器进程冲突 | 放弃nodriver，用 agent-browser eval |
| 翻页点击没反应 | 百度动态加载 | 直接URL加 `&pn=10` 翻页 |

## 方案切换决策树

```
agent-browser(主力) --失败2次--> chrome-devtools-mcp(备选) --失败--> nodriver(最后手段)
反爬场景：直接使用 CloakBrowser 隐身引擎
```

## 前置依赖

安装所有工具（一次性）：

```bash
npm install -g agent-browser chrome-devtools-mcp
pip install nodriver cloakbrowser
```

配置 agent-browser（可选，确保 headed 模式）：

```json
// ~/agent-browser.json
{ "headed": true }
```
