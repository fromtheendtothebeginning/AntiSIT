# 校园服务开放接口规约（/api/campus-open + 登录鉴权）

> 随本仓库开源（GPL-3.0）。行为基线：2026-10-05。
>
> **写作目标**：**接口形式兼容规约**——只看本文，就能用任意语言/框架实现出**相同接口形式**的客户端或服务端：路径、方法、请求/响应结构、状态码、错误语义一致。服务端内部机制不在本规约范围：登录鉴权的实现细节（密码存储、令牌签发与签名密钥等）由实现方自定，只需对外行为一致（§2）；上游学校系统的对接协议同理（§3 只约定本 API 自身的进出行为）。
> 凡「文案原文」均逐字摘自现有服务端实现——客户端可对 `detail` 做字符串匹配做程序化分支，不必依赖语言翻译。

- 生产 Base URL：`https://anticraft.top`（同源代理 `/api` → 后端）
- 下文所有路径均含 `/api` 前缀，直接拼在 Base URL 后。

---

## 目录

1. [通用约定](#1-通用约定)
2. [登录与令牌（接口形式）](#2-登录与令牌接口形式)
3. [校园开放接口（/api/campus-open）](#3-校园开放接口apicampus-open)
4. [状态码速查与错误文案对照](#4-状态码速查与错误文案对照)
5. [客户端实现核对清单](#5-客户端实现核对清单)
6. [curl 速查](#6-curl-速查)

---

## 1. 通用约定

| 项 | 约定 |
|---|---|
| 请求/响应编码 | JSON UTF-8；请求头 `Content-Type: application/json` |
| 鉴权方式 | `Authorization: Bearer <access_token>`（§2） |
| 成功响应 | 各接口自定义，**均含 `"ok": true` 字段**（登录/续期除外，见 §2） |
| 错误响应 | 统一 `{"detail": "<中文错误说明>"}`；**422 校验错误时 `detail` 是数组** |
| 422 结构 | `{"detail":[{"type":"greater_than_equal","loc":["body","zs"],"msg":"Input should be greater than or equal to 1","input":0}]}`，`loc` 指明出错字段路径 |
| 时间格式 | 数据字段（活动/考试/电费）为 `"YYYY-MM-DD HH:MM:SS"` 字符串；用户 `created_at` 为 ISO 8601（如 `2026-10-05T12:34:56`） |
| 限流依据 | 客户端 IP（经可信反向代理时取 `X-Forwarded-For` 末段）；超限统一 429 `{"detail":"请求过于频繁，请稍后再试"}` |
| 健康检查 | `GET /api/health`（无需鉴权）→ `{"status":"ok","message":"anticraft API is running"}` |
| CORS | 跨域策略由服务端自定，对非浏览器客户端无影响 |

---

## 2. 登录与令牌（接口形式）

登录是一个**黑盒接口**：客户端提交账号密码换取 Bearer 令牌。实现方内部如何存储密码、签发/签名令牌自定，但对外接口形式与行为必须一致。

### 2.1 登录

`POST /api/login`（无需鉴权）

```json
{ "username": "用户名", "password": "密码" }
```

成功 `200` → TokenResponse：

```json
{ "access_token": "<令牌字符串>", "token_type": "bearer", "user": { ...UserResponse } }
```

**UserResponse**（登录/续期响应的 `user` 字段结构，属于接口形式的一部分）：

```json
{ "id": 126, "username": "demo", "nickname": null, "avatar_url": null,
  "is_active": true, "role": "user", "created_at": "2026-10-05T12:34:56" }
```

| 字段 | 类型 | 说明 |
|---|---|---|
| id | int | 用户唯一 ID（服务端会话/凭据按此隔离） |
| username | string | 用户名 |
| nickname / avatar_url | string\|null | 昵称 / 头像 URL（可空） |
| is_active | bool | 是否启用（禁用后令牌立即失效） |
| role | string | `user` / `admin` |
| created_at | datetime | 注册时间 |

错误：`401`「用户名或密码错误」（用户不存在与密码错误同文案）；`403`「账号已被禁用」；`429`（同 IP 每分钟 10 次、同用户名每分钟 5 次）。

### 2.2 令牌形式与失效语义

- 携带方式：`Authorization: Bearer <access_token>`。
- 令牌有效期 **30 天**。
- 鉴权失败：携带了但令牌无效/过期/账号被禁用 → `401 {"detail":"无效的令牌"}`；完全未携带 `Authorization` 头 → `401 {"detail":"Not authenticated"}`。
- 客户端收到 401 → 清本地令牌、重新 `POST /api/login`。

### 2.3 续期（可选实现）

`POST /api/refresh`（需 Bearer）→ 用**仍然有效**的令牌换发全新 30 天令牌，`200` TokenResponse；令牌无效 → `401`。

官方客户端的用法（建议复刻但非必需）：解码令牌 payload 取 `exp`，剩余有效期 **< 15 天**时后台静默调本接口换新（并发请求共享同一次刷新）；即便从不续期也有 30 天兜底。

---

## 3. 校园开放接口（/api/campus-open）

### 3.0 设计与前置条件

**核心设计**：客户端只持站内账号令牌，**全程不传任何校园密码**。校园凭据在服务端按账号配置一次（加密存储），服务端全权负责：连校园内网（EasyConnect VPN）→ 登录验证码先 AI 自动识别（用该账号自己配置的识图模型），走不通（未开启 AI 识码 / 未配识图模型 / 识图失败）退回 need_captcha 手动输入 → 抓取并结构化数据。

**前置配置表**（每账号一份，服务端需提供配置能力；开放接口按账号读取）：

| 配置项 | 哪些接口需要 |
|---|---|
| 学号 + VPN 密码（=统一身份认证密码） | 隧道类全部：分数/成绩/活动/课表/考试 |
| 「AI 自动识别验证码」开关 | 隧道类全部（未开启时验证码退回手动输入，不报错） |
| 识图模型（视觉 AI Key + 模型） | 隧道类全部（缺省时验证码退回手动输入，不报错） |
| 校付宝支付密码 | 校园码 / 电费查询 / 电费充值 |
| 姓名（真实姓名） | 校园码 / 电费（校付宝登录用） |
| 默认寝室号（如 `24号楼1016`） | 电费查询 / 充值 |

**接口分类**：

| 类别 | 接口 | 依赖 |
|---|---|---|
| 隧道类（VPN） | `score` / `grades` / `activities` / `activities/{aid}` / `timetable/week` / `timetable/exams` | 校园内网，可能返回 202 |
| 直连类（校付宝公网） | `ecard` / `electricity/query` / `electricity/history` / `electricity/recharge` | 不占 VPN，隧道断开也能用，**绝不返回 202** |
| 本地状态 | `status` / `disconnect` | 不触上游 |

**接入流程**：

```
1. POST /api/login（站内账号）→ access_token（30 天）
2. 所有请求带 Authorization: Bearer <token>（临近过期 POST /api/refresh 续期）
3. 建议先 GET /status 检查 configured / has_pay_password / has_dorm / auto_captcha，引导用户补配置
4. 数据接口直接调：
   ├─ 202 {"vpn_connecting": true, "retry_after": 5} → 等 5 秒重试同一请求（服务器侧状态保留，重试接着走）
   ├─ 200 {"need_captcha": true, "mode": "xg"|"jwxt", "captcha_base64": "..."} → 弹手动验证码框
   │    提交 POST /captcha（见 §3.2）成功后重试同一数据请求；学校回「验证码」类错误换一张重输
   ├─ 401 → token 失效 → 重新 /api/login
   └─ 200 {"ok": true, ...} / 4xx {"detail": "..."}
```

**隧道类接口统一执行顺序**（每一步的失败码与文案见 §4 对照表）：

1. Bearer 鉴权（401）→ 2. 读取校园凭据，缺失 400 引导 → 3. 解密 VPN 密码 → 4. 校园基础设施就绪检查（Docker 不可用 503）→ 5. 确保 VPN 隧道：未连接则异步发起连接并在**本请求内等待至多 40 秒**（每 1.5 秒轮询一次，就绪判定 = 会话 connected 且隧道路由 > 0）；等待窗口内未就绪 → **202**；会话 failed → 视错误文案含「密码/账号」与否映射 401/502 → 6. 确保学工(CAS)/教务登录：需要验证码时先 AI 自动识别（最多 3 轮），走不通时取一张新验证码以 need_captcha 交回客户端手动输入 → 7. 抓取数据。

**并发与部署约束**（客户端必须知晓）：

- 学校侧限制**同一出口 IP 同时只有一条 VPN 隧道**：隧道类接口多账号并发会互踢（被踢方的下一次请求自动重连，表现为变慢或 202/502）。直连类接口不受影响。
- 同一账号的多个客户端（网页/App）**共享同一条隧道**（会话 key = 用户 ID），不存在互踢。
- 服务端有心跳保活/自动重连（北京时间 06:00–23:00）；客户端只需按 202/5 秒节奏重试。
- 隧道类接口首次调用最坏耗时 ≈ 40 秒等待 + 数据抓取：**客户端 HTTP 超时应设 ≥ 60 秒**（生产 nginx 代理超时 60s）。

### 3.0.1 手动验证码兜底（need_captcha）

隧道类接口在「需要验证码登录但无法自动识别」时（未开启 AI 识码 / 未配识图模型 / AI 识图失败 /
3 轮识别提交全错），返回 **HTTP 200**：

```json
{"need_captcha": true, "mode": "jwxt", "captcha_base64": "<PNG 的 base64>"}
```

- `mode`：`xg` = 统一身份认证（分数/活动），`jwxt` = 教务系统（成绩/课表/考试）
- 客户端弹出验证码输入框（换一张、失败原因提示与直连模式同款交互）

**提交验证码**：

`POST /api/campus-open/captcha`（Bearer），body `{"mode": "xg|jwxt", "captcha": "用户输入"}`

- `200 {"ok": true}` → 登录完成，**重试原数据请求**即可（服务端会话已建立，不再返回 need_captcha）
- `400 {"detail": "..."}` → 学校原文错误（如「验证码错误」）：detail 含「验证码」→ 换一张重输；
  含「密码/账号」→ 提示检查凭据，不要反复弹窗

**换一张验证码**：

`GET /api/campus-open/captcha?mode=xg|jwxt`（Bearer）→ `{"ok": true, "logged_in": false,
"captcha_base64": "..."}`；`logged_in: true` 表示期间已登录成功，直接重试原请求。

> 两次登录尝试之间的验证码是一次性的：失败的码不能退回重用，重输前必须先「换一张」取新码。

---

### 3.1 账号配置与 VPN 会话状态

`GET /api/campus-open/status`（Bearer）

```json
{
  "ok": true,
  "configured": true,
  "student_id_masked": "25****11",
  "has_pay_password": true,
  "has_dorm": true,
  "auto_captcha": true,
  "session": {
    "connected": true, "status": "connected", "error": null,
    "student_id_masked": "25****11", "socks_port": 12345, "http_port": 12346, "host": "127.0.0.1"
  },
  "cas_ready": true,
  "jwxt_ready": false
}
```

| 字段 | 说明 |
|---|---|
| configured | 是否已配置校园凭据（学号）；false 时隧道类接口必 400，客户端应引导用户补配置 |
| has_pay_password / has_dorm / auto_captcha | 对应缺项引导（直连类/隧道类分别检查） |
| session.status | `none`（无会话）/ `creating` / `connecting` / `connected` / `failed`；基础设施不可用时为 `unavailable`（附 error）。`connected` 是强判定：隧道路由已清零（被踢）会回落为 `connecting` |
| cas_ready / jwxt_ready | 学工(CAS)/教务登录态是否已建立；失效会在下次数据调用自动重登（AI 识码），客户端无需处理 |

`POST /api/campus-open/disconnect`（Bearer）→ `{"ok": true}`：断开当前账号 VPN 会话并丢弃登录客户端；下次数据调用自动重连。基础设施不可用时也返回 ok（无操作）。

### 3.2 第二课堂达标分数

`GET /api/campus-open/score`（Bearer，隧道类，学工）

```json
{
  "ok": true,
  "data": {
    "student": { "xh": "2511xxxx", "xm": "张三", "nj": "2025", "bmmc": "…学院", "zymc": "…专业", "bjmc": "…班" },
    "total": 12.5,
    "credit": 8.0,
    "groups": [
      { "name": "德育", "subtotal": 3.0, "rows": [ { "name": "…项目", "value": 1.0 } ] }
    ]
  }
}
```

- `total`=总要求值（上游 `zxs`），`credit`=实得值（上游 `sjxf`），无数据时二者为 null、`student` 为 `{}`。
- `groups` 由上游表头自动归类：表头字段 `fieldTh` 为大类名（组名），`dlxs*` 字段计为该组 `subtotal`，`rdxs*` 字段计为明细行 `{name: fieldName, value}`。

### 3.3 成绩单

`GET /api/campus-open/grades?xnm=<学年>&xqm=<学期码>`（Bearer，隧道类，教务）

| 参数 | 说明 |
|---|---|
| `xnm` | 学年，如 `2025`；留空=不限 |
| `xqm` | 学期码（正方约定）：**第一学期 `3` / 第二学期 `12`**；留空=不限 |

**两个参数都留空**时返回全部学期成绩，并在 `data.terms` 给出可选学期列表（客户端可先调一次获取全部学期码再做分学期切换）：

```json
{
  "ok": true,
  "data": {
    "grades": [
      { "kcmc": "高等数学", "cj": "92", "xf": "4.0", "jd": 4.2, "xfjd": 16.8,
        "kclbmc": "必修", "kcxzmc": "…", "khfsmc": "考试", "xqmmc": "…校区",
        "xnmmc": "2025-2026学年", "sfxwkc": "是" }
    ],
    "gpa": 3.86,
    "count": 18,
    "terms": [ { "xnm": "2025", "xqm": "3", "xnmmc": "2025-2026学年", "xqmmc": "第一学期" } ]
  }
}
```

- 字段含义：课程名 kcmc / 成绩 cj（可能是数字串也可能是等级制如「优」）/ 学分 xf / 绩点 jd / 学分绩 xfjd / 课程类别 kclbmc / 课程性质 kcxzmc / 考核方式 khfsmc / 校区 xqmmc / 学年 xnmmc / 是否外语课 sfxwkc。
- **绩点算法**（服务端重算，客户端直接展示即可，复刻服务端时须一致）：数值成绩 `jd = round(cj/10 − 5, 4)`（满绩 5.0）；等级制成绩用系统给的 jd（缺失按 0）；`xfjd = round(jd × xf, 4)`；`gpa = round(Σxfjd / Σxf, 4)`（Σxf=0 时为 0）。
- `terms` 按 `(xnmmc, xqm)` 排序；仅在全空参数时返回。

### 3.4 第二课堂活动列表

`GET /api/campus-open/activities`（Bearer，隧道类，学工）

```json
{
  "ok": true,
  "data": {
    "student_id": "2511xxxx",
    "activities": [
      {
        "id": "1a2b3c",
        "name": "xx讲座",
        "dlmc": "思想成长", "lbmc": "讲座报告",
        "host": "主办方",
        "bm_start": "2026-10-01 10:00:00", "bm_end": "2026-10-09 22:00:00",
        "start": "2026-10-10 14:00:00", "end": "2026-10-10 16:00:00",
        "campus": "奉贤",
        "backfill": false,
        "quota": "30 人",
        "signup": { "qq": ["123456789"], "phone": [], "tips": ["扫码"], "contact_lines": ["…"] },
        "hdms": "活动说明全文（≤2000 字）"
      }
    ]
  }
}
```

| 字段 | 推导规则（服务端完成；复刻时需一致） |
|---|---|
| bm_start / bm_end / start / end | 上游报名开始/截止、活动开始/结束时间字符串（可能为 null） |
| campus | 名称+说明里含「奉贤」「徐汇」字样判定：两含=`奉贤+徐汇`，单含取其一，均无=`未标注` |
| backfill | 活动开始时间早于报名开始时间=true（事后补录型活动） |
| quota | 从说明文本正则提取「人数/名额/限/招收/招募/录取/报名人数 N 人」→ `"N 人"`；说明含「人数不限/名额不限」→ null；找不到 → null |
| signup | 报名线索：`qq`（群号模式正则提取的 5-12 位数字，剔除与手机号重复者）、`phone`（`1[3-9]` 开头 11 位）、`tips`（说明中出现的固定关键词：扫码/二维码/扫码进群/报名成功/请勿申请/无需报名）、`contact_lines`（含 QQ群/群号/加群/扫码/钉钉/微信群/联系人/联系电话/咨询电话/报名方式/报名链接/报名请/申请加入/入群 等关键词、且不含「群体/社群/人群/群众/成群/超群」误判词的原始行，最多 3 行）——各键仅在非空时出现 |
| hdms | 活动说明全文，截断 2000 字符 |

**报名状态（即将开始/报名中/已结束）服务端不判定**：客户端用本机时间对 `bm_start`/`bm_end` 自行比较。

### 3.5 单个活动详情

`GET /api/campus-open/activities/{aid}`（Bearer，隧道类，学工；`aid` = 活动列表里的 `id`）

```json
{ "ok": true, "data": { "id": "1a2b3c", "hdms": "活动说明全文（不截断）", "quota": "30 人", "signup": { "qq": ["…"] } } }
```

### 3.6 课表单周查询

`POST /api/campus-open/timetable/week`（Bearer，隧道类，教务）

```json
{ "xnm": "2025", "xqm": "3", "zs": 1 }
```

| 字段 | 校验 |
|---|---|
| xnm / xqm | 字符串，同 §3.3（可空串） |
| zs | 周次，整数 **1-40**（缺省 1）；越界 → 422 |

```json
{
  "ok": true, "zs": 1,
  "courses": [
    { "name": "高等数学", "place": "二教E101", "teachers": "王老师",
      "code": "MA1101", "clazz": "…教学班", "day": 0, "slotStart": 0, "slotEnd": 1 }
  ],
  "dates": [ { "xqj": 1, "rq": "2026-09-07" } ],
  "xnmc": "2025-2026学年",
  "nj": "2025"
}
```

| 字段 | 说明 |
|---|---|
| day | 0-6（**0=周一**），由上游 xqj（1-7）减 1，越界夹紧到 0-6 |
| slotStart / slotEnd | **大节下标**（0 起、含端点，最大 10）：由上游节次串 `jcs`（如 `"3-4"`）减 1 得到；单节 `"5"` → 起止相等。解析失败或越界（slotEnd>10）的行被**静默丢弃** |
| code / clazz | 课程代码 / 教学班：取自上游 `kcb_id`/`jxbmc`（32 位 GUID 形态的内部 ID 会被跳过、尝试候选字段，全部无效则为空串）。**code+clazz+day+slot 可作合并去重键** |
| dates | 该周 7 天的真实日期：`xqj` 1-7（周一~周日）、`rq` `YYYY-MM-DD`；用于把周次锚定到日期 |
| xnmc / nj | 学年名；`nj`=年级（入学学年，用于把「大一上~大四下」锚定真实学年） |

**拉整学期**：对 `zs=1,2,3,…` 循环调用，直到返回 400「该周没有课表数据（可能已超出学期范围）」即止；同一门课每周重复出现，按 `code+clazz+day+slotStart+slotEnd` 去重合并。

### 3.7 考试安排

`POST /api/campus-open/timetable/exams`（Bearer，隧道类，教务）

```json
{ "xnm": "2025", "xqm": "3" }
```

```json
{
  "ok": true,
  "exams": [
    { "name": "高等数学", "ksmc": "期末考试", "date": "2026-01-12",
      "start": "08:00", "end": "09:40", "place": "二教E101", "seat": "12", "ksfs": "笔试" }
  ]
}
```

- 上游考试时间为 `kssj` 形如 `2026-01-12(8:00-9:40)`，服务端解析并**补零规范化**为 `date` + `start`/`end`（`HH:MM`）；解析失败的行被静默丢弃。
- 字段含义：考试名次 ksmc / 地点 place / 座位号 seat / 考试方式 ksfs。

### 3.8 校园码（付款码）

`GET /api/campus-open/ecard`（Bearer，**直连类**）

```json
{
  "ok": true,
  "data": {
    "image": "iVBORw0KGgo…（二维码 PNG base64，服务端无渲染库时为 null）",
    "type": "image/png",
    "code": "付款码原文（客户端可自行渲染二维码）",
    "card_balance": 56.7,
    "refresh": 55
  }
}
```

- 需要：学号 + **支付密码** + **姓名**（缺支付密码 400「尚未设置支付密码」；缺姓名在上游报错，400 文案含「缺少姓名」）。
- `card_balance`（一卡通钱包余额，元）取不到时为 null，不影响取码——**码是主数据**。
- 码有效约 55 秒：客户端按返回的 `refresh` 定时重新调用。

### 3.9 电费余额查询

`POST /api/campus-open/electricity/query`（Bearer，**直连类**，无请求体）

```json
{ "ok": true, "data": { "balance": 23.45, "card_balance": 56.7, "remain": null, "dorm": "X31-123" } }
```

| 字段 | 说明 |
|---|---|
| balance | 宿舍电费余额（元，两位小数；上游缺该字段时 null） |
| card_balance | 校园卡余额（元；可 null） |
| remain | 剩余度数——上游接口不提供，恒为 null（保留字段） |
| dorm | 本次查询用的寝室串（服务端配置原文） |

- 需要：默认寝室（缺 → 400「尚未填写默认寝室，请到「我的 → 校园服务」填写」）+ 支付密码。
- 每次成功查询**服务端自动落一条电费历史**（§3.10 可读出）；网络类失败且本人 VPN 已连接时服务端自动借道本人隧道重试一次，客户端无需处理。
- 寝室串由服务端解析（支持 `24号楼1016` / `24-1016` 等），楼号换算 `buildid = 楼号 + 1`（复刻上游协议时注意）。

### 3.10 电费历史

`GET /api/campus-open/electricity/history?days=90`（Bearer，直连类；days 取值 1-365，越界自动夹紧，默认 90）

```json
{ "ok": true, "records": [ { "balance": 23.4, "remain": null, "dorm": "X31-123",
  "time": "2026-10-03 22:00:05", "recharge": 0 } ] }
```

按 `time` **升序**（直接喂折线图）；`recharge > 0` 表示该记录由充值产生、值为充值金额。服务端每晚 22:00（北京时间）对已填寝室的账号自动采集，历史数据即使客户端不查询也在增长。

### 3.11 电费充值

`POST /api/campus-open/electricity/recharge`（Bearer，直连类）

```json
{ "amount": 50 }
```

```json
{ "ok": true, "message": "充值成功", "data": { "balance": 73.45, "card_balance": 56.7, "amount": 50 } }
```

- 金额约束 `0 < amount ≤ 500`（元），否则 400「金额须在 0.01 - 500 元之间」。
- 上游流程：创建订单 → 余额支付（金额按分提交）；任一步失败 → 400（文案「充值失败：…」或上游 retmsg）。
- ⚠️ **扣款接口：服务端只调用一次、绝不重试。客户端同样必须禁止自动重试**——超时/网络错误后应先调 §3.9 查询余额确认是否已扣款，再决定下一步。
- 成功后服务端复查一次最新余额（可能失败 → `data.balance` 为 null），并落一条带 `recharge_amount` 的历史记录；`data.card_balance` 为支付后的校园卡余额。

---

## 4. 状态码速查与错误文案对照

### 4.1 状态码速查

| 码 | 含义 | 客户端动作 |
|---|---|---|
| 200 | 成功 | — |
| 202 | VPN 隧道建立中（`{"vpn_connecting":true,"retry_after":5}`，仅隧道类接口） | 等 `retry_after` 秒重试**同一请求**，可重试 6-10 次 |
| 400 | 参数错误 / 凭据未配置 / 未开启自动识码 / 上游业务失败 | 按 `detail` 提示（对照下表） |
| 401 | 令牌无效/过期/禁用（`无效的令牌`/`Not authenticated`），或 VPN 登录失败（校园密码错误） | 前者重新 `/api/login`；后者提示检查校园凭据 |
| 403 | 账号已被禁用（登录时） | — |
| 422 | 参数校验失败（detail 为数组） | 修参数 |
| 429 | 限流 | 等待后重试 |
| 500 | 服务端内部错误 | 稍后重试 |
| 502 | VPN 会话创建失败 / 校园系统侧失败 / 自动登录未成功 | 稍后重试 |
| 503 | 校园基础设施（Docker）不可用 | 联系服务维护者 |

### 4.2 错误文案原文对照（程序化分支用，逐字匹配）

| detail（原文） | 码 | 触发条件 → 客户端应做 |
|---|---|---|
| `无效的令牌` | 401 | 令牌无效/过期/被禁用 → 重新登录 |
| `Not authenticated` | 401 | 未携带 Authorization 头 → 补令牌或重新登录 |
| `用户名或密码错误` | 401 | 登录凭据错（不区分用户是否存在） |
| `账号已被禁用` | 403 | 登录时账号被禁用 |
| `请求过于频繁，请稍后再试` | 429 | 登录限流（10/min/IP、5/min/用户名） |
| `尚未填写校园服务凭据，请到「我的 → 校园服务」填写` | 400 | 未配置学号（隧道类） |
| `凭据解密失败，请重新填写` | 400 | 服务端解密失败 → 重新配置凭据 |
（已移除）`该账号未开启 AI 自动识别验证码…` / `尚未配置识图模型…` 原 400 引导 → 改为 need_captcha 手动兜底（见 §3.0.1） |
| `校园服务未就绪（Docker 不可用）：<原因>` | 503 | 基础设施 |
| `VPN 会话创建失败：<原因>` | 502 | 容器创建失败 |
| `登录失败：账号或密码错误（若确认无误，可能是学校侧暂时拒绝，请稍后重试）` | 401 | VPN 登录被拒（detail 含「密码/账号」时服务端映射 401） |
| `登录失败（容器已退出），请检查账号密码或网络` | 401 | VPN 容器退出 |
| `连接超时：隧道未就绪（同账号可能已在别处登录），请稍后重试` | 502 | 建隧道超时（同账号单会话互踢场景） |
| `登录验证码获取失败，请稍后重试` | 502 | 上游验证码图获取失败 |
| `验证码识别失败，请稍后重试` | 502 | AI 识码失败（已改为降级 need_captcha，仅旧版服务端返回） |
| `统一身份认证自动登录未成功，请稍后重试` / `教务系统自动登录未成功，请稍后重试` | 502 | 3 轮识码重试后仍失败（已改为降级 need_captcha，仅旧版服务端返回） |
| `该周没有课表数据（可能已超出学期范围）` | 400 | 课表循环终止条件 |
| `尚未设置支付密码` | 400 | 校园码/电费缺支付密码 |
| `尚未填写默认寝室，请到「我的 → 校园服务」填写` | 400 | 电费缺寝室 |
| `校园码获取失败：<上游原因>` / `电费查询失败：<上游原因>` / `充值失败：<上游原因>` | 400 | 上游校付宝失败（含「缺少姓名，请在「我的 → 校园服务」填写」） |
| `金额须在 0.01 - 500 元之间` | 400 | 充值金额越界 |
| 学工/教务侧透传文案（如 `登录态失效，请重新查询`、`教务系统响应超时，请重试`、上游 msg） | 400 | 数据抓取层失败 → 通常重试即可；「登录态失效」类服务端下次自动重登 |

---

## 5. 客户端实现核对清单

1. **登录**：`POST /api/login` 存 `access_token` + `user`；此后每个请求带 `Authorization: Bearer`。
2. **401 统一处理**：收到 401 清凭证重新登录（注意区分 `无效的令牌`/`Not authenticated` 与 VPN 密码错误——后者不要清站内令牌，按 detail 提示）。
3. **202 重试循环**：隧道类接口收到 202 → 等 `retry_after`(5s) 重试同一请求，最多 ~10 次（建隧道最坏数分钟）；超限提示稍后再来。**直连类接口永远不该收到 202**。
4. **超时**：隧道类 HTTP 超时 ≥ 60s；直连类 ≥ 30s。
5. **静默续期**（建议）：令牌剩余 < 15 天时调 `/api/refresh` 换新（解码 payload 取 exp 即可）；并发防抖；失败不打扰。
6. **引导配置**：先调 `GET /status`，按 `configured / auto_captcha / has_pay_password / has_dorm` 缺项引导用户在服务端补配置。`need_captcha` 手动兜底见 §3.0.1：弹验证码框 → POST 提交 → 重试原请求；提交错误 detail 含「验证码」先 GET 换一张再弹。
7. **成绩分学期**：先空参调 `/grades` 拿 `data.terms`，再按 `xnm`+`xqm` 逐学期查询。
8. **课表整学期**：`zs=1,2,…` 循环至 400「该周没有课表数据」；课程按 `code+clazz+day+slotStart+slotEnd` 去重；用 `dates` 与 `nj` 锚定真实日期与年级。
9. **活动报名状态**：客户端按本机时间比较 `bm_start`/`bm_end`；`backfill=true` 的活动是补录型。
10. **校园码**：每 `refresh`(55)s 重新取码；`image` 为 null 时用 `code` 自行渲染二维码。
11. **充值防重**：`/electricity/recharge` **绝不自动重试**；失败后先查余额确认。
12. **限流节流**：登录有分钟级限流，失败重试加退避。
13. **并发约束提示**：多账号同时跑隧道类接口会互踢（学校单隧道限制）；错峰或接受偶发 202/502 重试。

---

## 6. curl 速查

```bash
BASE=https://anticraft.top

# 登录换令牌（30 天）
TOKEN=$(curl -s $BASE/api/login -H "Content-Type: application/json" \
  -d '{"username":"用户名","password":"***"}' \
  | python -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

# ── 状态 / 断开 ──
curl -s $BASE/api/campus-open/status     -H "Authorization: Bearer $TOKEN"
curl -s -X POST $BASE/api/campus-open/disconnect -H "Authorization: Bearer $TOKEN"

# ── 隧道类（202 时等 5 秒重试）──
curl -s $BASE/api/campus-open/score   -H "Authorization: Bearer $TOKEN"
curl -s "$BASE/api/campus-open/grades?xnm=2025&xqm=3" -H "Authorization: Bearer $TOKEN"
curl -s $BASE/api/campus-open/activities -H "Authorization: Bearer $TOKEN"
curl -s $BASE/api/campus-open/activities/1a2b3c -H "Authorization: Bearer $TOKEN"
curl -s $BASE/api/campus-open/timetable/week  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"xnm":"2025","xqm":"3","zs":1}'
curl -s $BASE/api/campus-open/timetable/exams -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"xnm":"2025","xqm":"3"}'

# ── 直连类（不占 VPN）──
curl -s $BASE/api/campus-open/ecard -H "Authorization: Bearer $TOKEN"
curl -s -X POST $BASE/api/campus-open/electricity/query -H "Authorization: Bearer $TOKEN"
curl -s "$BASE/api/campus-open/electricity/history?days=90" -H "Authorization: Bearer $TOKEN"
curl -s $BASE/api/campus-open/electricity/recharge -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"amount":50}'
```
