# PotPlayer 实时字幕翻译（火山引擎版）README

> 这个脚本是把你原来的 **DeepL** 版本改成 **火山引擎机器翻译（TranslateText）**。
> 纯 **AngelScript**，不依赖任何外部程序，按照 PotPlayer 的原有脚本接口加载与调用。

---

## 功能与特性

* 实时把当前字幕段发送到火山引擎 **TranslateText** 接口并返回译文
* 纯脚本实现 **HMAC-SHA256** 签名，直接 `POST` 到 `open.volcengineapi.com`
* 自动读取服务端 `Date` 用作签名时间（不依赖本机时钟）
* 支持多语种，源语言为空则自动识别（由服务端完成）

---

## 你需要准备什么

1. **火山引擎账号**，并在控制台创建 **AccessKey ID** 与 **SecretAccessKey**（AK/SK）。
2. 确保该 AK/SK 拥有机器翻译相关权限（等价于 `TranslateFullAccess` 或包含此能力的策略）。
3. 可访问 `https://open.volcengineapi.com/` 的网络环境（直连或走你系统的网络代理均可，只要 PotPlayer 能连上）。

> 脚本默认区域与服务：`REGION = cn-north-1`，`SERVICE = translate`，RPC 端点固定为
> `https://open.volcengineapi.com/?Action=TranslateText&Version=2020-06-01`

---

## 安装

* 把脚本文件（你刚拿到的 `.as`）**放在你原 DeepL 脚本的同一位置**并替换（保持原有头部/导出函数不变即可正常被 PotPlayer 识别加载）。
* 如果你不确定脚本目录，就按你目前使用的字幕翻译脚本放置方式来处理——此脚本与 DeepL 版是同级替换，不需要改变 PotPlayer 的加载方式。

---

## 首次配置

1. 打开 PotPlayer，进入字幕翻译脚本的**登录/设置**界面（和你原来 DeepL 脚本的入口一致）。
2. 在登录框中：

   * **AccessKey ID**：填你的 **AK**
   * **SecretAccessKey**：填你的 **SK**
3. 保存/确定。脚本会在第一次翻译时自动请求服务端时间并缓存 5 分钟。

> AK/SK 仅保存在脚本的内存变量里；点击“登出”或重启播放器后会清空。

---

## 使用

* 源语言（Source）：留空表示**自动识别**；也可以手动指定（如 `en`、`ja`、`ru` 等）。
* 目标语言（Target）：必填。常用 `zh`、`en`、`ja`、`ko`……
* 字幕出现时，脚本会把本段文本封装为：

  ```json
  {
    "TextList": ["当前字幕文本"],
    "TargetLanguage": "zh",
    "SourceLanguage": "en" // 源为空则不带该字段
  }
  ```

  并签名后 `POST` 到接口；成功时返回：

  ```json
  {
    "TranslationList": [
      { "Translation": "译文...", "DetectedSourceLanguage": "en", "Extra": null }
    ],
    "ResponseMetadata": { ... }
  }
  ```
* 对于 **阿拉伯语/波斯语/希伯来语**，脚本会在返回值前加 RTL 控制符，保证显示方向正常。

---

## 语言代码（可用示例）

* 源语言（可为空=自动）：`ar bg zh cs da nl en et fi fr de el hu id it ja ko lv lt nb pl pt ro ru sk sl es sv tr uk`
* 目标语言：同上。脚本会把 `en-gb/en-us` 折叠为 `en`，`pt-pt/pt-br` 折叠为 `pt`，`zh-*` 折叠为 `zh`。
* 需要更细的地区码？可以到脚本里的 `NormalizeSrc/NormalizeDst` 放开收敛规则。

---

## 常见问题 & 排错

### 1) 返回空串或“\[Volc Error] …”

* **403 / SignatureMismatch**

  * 核对 AK/SK 是否正确；
  * 确认网络没有中间设备篡改 Header（某些企业代理会加/改头导致签名验证失败）；
  * 等 5 分钟（服务端时间缓存过期后会重新获取 `Date`）。
* **401 / Unauthorized**

  * AK/SK 没有对应的权限策略。去控制台给这对 AK/SK 补权限。
* **429 / Throttling**

  * 触发了限流。字幕过于频繁时适当降低调用频率（把多条很短的行合并为一条再发）。
* **400 / InvalidParam**

  * 语言代码不被支持；文本过长或 JSON 非法。检查目标语言是否存在，文本中是否包含未转义的 `"` 或奇怪控制符。

### 2) 依赖本机时间会不会签名失败？

* 不依赖。脚本第一次会向 `open.volcengineapi.com` 发请求，读 **响应头的 `Date`** 来当作 `X-Date`；之后 5 分钟内复用。

### 3) 我需要挂系统代理才能出网

* 只要 PotPlayer 的 HTTP 栈能出到公网即可；脚本用的就是 PotPlayer 自带的 `HostUrlGetString` 系列。若公司代理会做 HTTPS MITM，请确保能正确建立到 `open.volcengineapi.com` 的 TLS。

### 4) 如何验证脚本已成功发起请求？

* 打开 PotPlayer 的脚本日志/调试窗口（你平常定位脚本问题用的同一套方式）。
* 或者把字幕切到英文，再把目标设为 `zh`，看是否出现中文。

---

## 性能与策略建议

* **合并发送**：默认一段字幕一发。你要更稳，可以在脚本里把同一时间窗内的多个短句合并成一个 `TextList`，减少 QPS。
* **退避重试**：对 `429/5xx` 做 100~~300ms 指数退避重试 1~~2 次就够了。
* **简单缓存**：上一条字幕与当前字幕完全相同则直接返回上次结果（可减小波动）。

---

## 安全提示

* AK/SK 只存在脚本进程内存；不要把填好 AK/SK 的脚本文件分发给别人。
* 如需多人共用，建议创建**子账号**与**最小权限策略**，而不是暴露主账号密钥。

---

## 可调项（脚本顶部常量）

* `REGION`（默认 `cn-north-1`）
* `SERVICE`（默认 `translate`）
* `ENDPOINT_HOST` / `ENDPOINT_URL`（默认 RPC 端点）
* `UserAgent`（默认 `PotPlayer-Volcengine/1.0`）

---

## 变更记录（相对 DeepL 版）

* ✅ 改为火山引擎 RPC 模式（签名 + POST）
* ✅ `JsonParse` 改为解析 `TranslationList[*].Translation`
* ✅ 登录框新增 **SecretAccessKey** 输入（沿用原有头部接口，不新增自定义入口）
* ✅ 自动获取服务端时间，避免本机时钟问题

---

如果你要扩展：**批量 TextList、领域/术语参数、最短路径缓存、错误分级 UI**——直接说你要的策略，我把对应段落插上去就行。
