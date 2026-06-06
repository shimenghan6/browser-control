---
name: browser-control
description: |
  浏览器操控统一入口。自动选择最佳方案：agent-browser CLI为主，eval JS为点击备选，chrome-devtools-mcp为备选，nodriver为最后手段。支持CloakBrowser隐身引擎。
  触发条件："打开浏览器", "搜索xxx", "搜一下xxx", "打开xxx网站", "浏览器搜",
  "帮我在网上查xxx", "用百度搜索", "上京东", any browser/search request.
---

# 浏览器操控技能 - 五层架构

**★ 方案零：已有CDP窗口直连（最高优先级）** → agent-browser(主力) → chrome-devtools-mcp(备选) → nodriver(最后手段)
反爬场景：CloakBrowser隐身引擎

## 核心原则

1. **一次到位**：直接选对工具和页面，不要反复切换尝试
2. **不阻塞**：脚本不加 `input()` 等交互，执行完保持浏览器窗口让用户看到
3. **用户可见**：agent-browser 永远加 `--headed`
4. **卡住自愈**：同一方案卡住2次立刻换方案，不等用户问，不反复死磕
5. **★ 已有窗口不新开（铁律）**：如果用户 Edge 已开 CDP 端口(9222)，必须用 Python + CDP WebSocket 操控已有标签页，不新开窗口/标签页。agent-browser --cdp 也会开新标签页，用户不接受。

## 自动路由规则

```
步骤0: curl http://127.0.0.1:9222/json/version
  ├─ 有返回 → ★ 方案零：Python + CDP WebSocket 直连已有标签页（不新开窗口）
  └─ 无返回 → CDP 端口未开
                ├─ 用户明确说"我有浏览器"/"用现有窗口" → 🛑 停止！自动帮用户开启CDP：
                │     1. 不杀进程！用独立临时profile启动Edge：
                │        start msedge --remote-debugging-port=9222 --user-data-dir="%USERPROFILE%/.cache/edge-cdp" "https://github.com"
                │     2. 等4秒 → curl验证端口 → 进入方案零
                │     3. 注意：这个新Edge窗口没有用户的登录态，需要用户手动登录一次
                │     4. 如果用户不愿新开 → 给出手动命令让他们关闭所有Edge后带端口重启
                │
                └─ 用户没提现有窗口 → 方案一 agent-browser --headed
                                           ├─ 成功 → 继续
                                           └─ 失败2次 → chrome-devtools-mcp
                                                         ├─ 成功 → 继续
                                                         └─ 失败 → nodriver(最后)
反爬场景：CloakBrowser 隐身引擎
```

| 优先级 | 方案 | 触发条件 |
|--------|------|---------|
| **0（最高）** | **Python + CDP WebSocket 直连已有标签页** | `curl http://127.0.0.1:9222/json/version` 有返回 |
| 🛑 **中断** | **提示用户开启CDP端口** | CDP DOWN + 用户说"我有浏览器"/"用现有窗口" |
| 1 | agent-browser | CDP DOWN + 用户没提现有窗口 |
| 2 | chrome-devtools-mcp | agent-browser 卡住2次 |
| 3 | nodriver | 前两者均失败 |
| - | CloakBrowser | 反爬网站 |

---

## 方案零：Python + CDP WebSocket 直连已有标签页（最高优先级）

**触发条件：`curl http://127.0.0.1:9222/json/version` 返回正常 JSON。用户 Edge 已开 CDP 端口时，必须用此方案——不开任何新窗口/标签页。**

### 核心原理

agent-browser 的致命缺陷：`--cdp 9222` 虽然连上了用户浏览器，但 `open` 命令会新开标签页。用户看到"被操控开新页"体验极差。

解决方案：绕过 agent-browser，用 Python `websockets` 库直接连 CDP WebSocket，在用户当前标签页上操作。

### 第一步：检查 CDP 端口

```bash
curl -s http://127.0.0.1:9222/json/version
# 返回 Browser/Protocol-Version → CDP 端口已开 → 走方案零
# 连接失败 → CDP 未开 → 走方案一 agent-browser
```

### 第二步：列出已有标签页

```bash
python -c "
import urllib.request, json
resp = urllib.request.urlopen('http://127.0.0.1:9222/json')
pages = json.loads(resp.read())
for i, p in enumerate(pages):
    print(f'[{i}] {p.get(\"title\",\"\")[:60]} | {p.get(\"url\",\"\")[:80]}')
"
```

### 第三步：在已有标签页执行 JS（填表/点击/读取）

```python
import asyncio, json, urllib.request, websockets

async def cdp_eval(url_match, script):
    """在url包含url_match的已有标签页执行script，不新开窗口"""
    resp = urllib.request.urlopen('http://127.0.0.1:9222/json')
    pages = json.loads(resp.read())
    
    target = next((p for p in pages if url_match in p.get('url', '')), None)
    if not target:
        raise Exception(f'未找到包含 {url_match} 的标签页')
    
    print(f"操控已有标签页: {target['title'][:60]}")
    
    async with websockets.connect(target['webSocketDebuggerUrl']) as ws:
        await ws.send(json.dumps({'id': 1, 'method': 'Runtime.enable'}))
        await ws.recv()
        
        await ws.send(json.dumps({
            'id': 2, 'method': 'Runtime.evaluate',
            'params': {'expression': script, 'returnByValue': True}
        }))
        result = await ws.recv()
        return json.loads(result)

# 使用示例：在用户已打开的 github.com/new 页面创建仓库
result = asyncio.run(cdp_eval('github.com/new', '''
    (() => {
        const s = Object.getOwnPropertyDescriptor(
            window.HTMLInputElement.prototype, 'value'
        ).set;
        const inp = document.getElementById('repository-name-input');
        s.call(inp, 'my-repo');
        inp.dispatchEvent(new Event('input', {bubbles: true}));
        return inp.value;
    })()
'''))
print(result)
```

### 第四步：等 React 校验后点击（拆分两步）

```python
# Step 1: 填表
asyncio.run(cdp_eval('github.com/new', '填充表单的JS...'))

# Step 2: 等待 React 校验
await asyncio.sleep(2)

# Step 3: 点击提交
asyncio.run(cdp_eval('github.com/new', '''
    (() => {
        const btns = document.querySelectorAll('button[type="submit"]');
        for (const btn of btns) {
            if (btn.textContent.includes('Create repository')) {
                btn.click();
                return 'clicked';
            }
        }
        return 'not found';
    })()
'''))

# Step 4: 验证跳转
await asyncio.sleep(3)
asyncio.run(cdp_eval('github.com', 'window.location.href'))
```

### 方案零 vs agent-browser --cdp 对比

| 行为 | agent-browser --cdp | Python CDP WebSocket |
|------|---------------------|---------------------|
| 连接已有浏览器 | ✓ | ✓ |
| 新开标签页 | ✗ 会新开 | ✓ 在已有标签页操作 |
| SPA 填表 | eval 无区别 | eval 无区别 |
| 用户感知 | "又被开了新页" | "就在我当前页面操作" |

### 依赖

```bash
pip install websockets
```

---

## 方案一：agent-browser（CDP 端口未开时使用）

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
| 用户已有浏览器+CDP端口已开 | 这是最高优先级场景 | **★ 切方案零：Python CDP WebSocket 直连，不新开窗口** |
| agent-browser --cdp 会新开标签页 | agent-browser 不支持指定已有标签页 | **不要用 agent-browser --cdp！用方案零 Python CDP WebSocket** |
| `--headed ignored` 警告 | daemon已在运行 | `agent-browser close --all` 后重试 |
| click @eXX 返回Done但页面没跳转 | daemon headless模式 | 改用 `agent-browser eval "document.querySelectorAll('h3 a')[N].click()"` |
| 同一方案连续失败2次 | 当前方案不适用 | **切换方案二 chrome-devtools-mcp** |
| chrome-devtools-mcp也无法完成 | 网站兼容性问题 | 切方案三 nodriver（最后保底） |
| 遇到验证码/反爬拦截 | 被Bot检测到 | 切 CloakBrowser 隐身引擎 |
| nodriver `uc.start()` 卡住 | 浏览器进程冲突 | 放弃nodriver，用 agent-browser eval |
| 翻页点击没反应 | 百度动态加载 | 直接URL加 `&pn=10` 翻页 |
| snapshot 返回空 | SPA/React页面，DOM动态渲染 | 放弃 snapshot，直接用 `eval` 查 DOM |
| `inp.value = 'x'` 后表单无效 | React 劫持了 input setter | 用 `nativeInputValueSetter` + `dispatchEvent` |
| eval 内 `setTimeout` 不触发 | eval 同步返回后脚本退出 | 拆成两个 eval + shell `sleep` 等待 |
| 连不上已有浏览器窗口 | 浏览器未开 CDP 调试端口 | 关闭所有窗口，`msedge --remote-debugging-port=9222` 重启 |

## eval 高级技巧

### React 表单输入（nativeInputValueSetter）

React 劫持了 `<input>` 的 value setter，直接赋值不触发状态更新：

```js
// ❌ 不生效
document.getElementById('repo-name').value = 'my-repo';

// ✅ 生效
const nativeSetter = Object.getOwnPropertyDescriptor(
  window.HTMLInputElement.prototype, 'value'
).set;
nativeSetter.call(inp, 'my-repo');
inp.dispatchEvent(new Event('input', {bubbles: true}));
inp.dispatchEvent(new Event('change', {bubbles: true}));
```

### eval 中禁止 setTimeout/async

eval 同步返回后脚本立即退出，异步回调来不及执行：

```bash
# ❌ 不生效 —— setTimeout 回调不会触发
agent-browser eval "setTimeout(() => btn.click(), 500); 'done'"

# ✅ 拆成两步
agent-browser eval "fillForm(); 'filled'"
sleep 2
agent-browser eval "document.querySelector('button').click(); 'clicked'"
```

### CDP 连接已有浏览器

**有 CDP 端口时（方案零）**：用户 Edge 已开 `--remote-debugging-port=9222`。不要用 agent-browser（会新开标签页），直接用 Python CDP WebSocket 操控已有标签页。详见上方"方案零"。

**无 CDP 端口时**：用户浏览器未开调试端口。需要用户手动重启：

```bash
# 关闭所有 Edge
taskkill //F //IM msedge.exe

# 重启带调试端口
"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" \
  --remote-debugging-port=9222 \
  "https://目标URL"

# 验证端口
curl http://127.0.0.1:9222/json/version

# ★ 然后用方案零 Python CDP WebSocket，不要用 agent-browser！
```

## 方案切换决策树

```
1. curl http://127.0.0.1:9222/json/version → 通？
   ├→ YES → ★ 方案零：Python CDP WebSocket 直连已有标签页（不新开窗口）
   └→ NO  → agent-browser --headed
              ├→ 成功 → 继续
              └→ 失败2次 → chrome-devtools-mcp
                            ├→ 成功 → 继续
                            └→ 失败 → nodriver(最后手段)
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
