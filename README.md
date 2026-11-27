# AntiSIT

校园服务 App：课程表 / 校园码 / 成绩 / 第二课堂 / 电费，一站式校园助手。Flutter 编写的 Android / Windows 客户端。

**官网**：<https://anticraft.top/antiSIT/>（源码在 [site/](site/)，React + Vite 纯静态，改内容动 [site/src/lib/data.js](site/src/lib/data.js)，部署见 [site/README.md](site/README.md)）。

[![GitHub tag](https://img.shields.io/github/v/tag/fromtheendtothebeginning/AntiSIT?label=GitHub&logo=github&color=2f81f7)](https://github.com/fromtheendtothebeginning/AntiSIT/tags)
[![Gitee tag](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fgitee.com%2Fapi%2Fv5%2Frepos%2Fender123%2FAntiSIT%2Freleases%2Flatest&query=%24.tag_name&label=Gitee&logo=gitee&color=c71d23)](https://gitee.com/ender123/AntiSIT/tags)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

## 下载

- **Android 7.0+**：[GitHub Releases](https://github.com/fromtheendtothebeginning/AntiSIT/releases) 或 [Gitee Releases](https://gitee.com/ender123/AntiSIT/releases) 下载 `AntiSIT-x.y.z.apk` 直接安装（首次需允许「未知来源」），同名 `.sha256` 可校验完整性。
- **应用内更新**：「我的 → 检查更新」是二级页面——分别显示**稳定版**与**内测版**有没有更高版本，可一键切渠道，也能关掉新版本弹窗；下载先校验 `.sha256`，再核对包名与签名才交给系统安装器；更新源 Gitee 优先，GitHub 与 anticraft.top 镜像兜底；装完自动删包，不会一直占空间。
- **两个发布渠道**：稳定版打 `v1.48.0` tag 发正式 Release；内测版 `version` 写成 `1.48.0-dev.2+…`、打 `dev-1.48.0-dev.2` tag 发 prerelease。App 按版本号里的预发布段区分两条线。
- **Windows**：CI 不发 Windows 包，需自行构建（见下方「构建」）。

同一套接口支持两种接入方式（「我的 → 连接设置」切换）：

| 接入方式 | 需要填写 | 校园数据怎么来 |
|---|---|---|
| **服务器模式** | 服务器地址（IP / 域名，可带端口）+ 该服务器的账号密码 | 由服务器代连校园内网（VPN 隧道 + AI 识码），App 不接触校园密码 |
| **直连模式** | 学校系统地址 + 校园凭据（学号 / 统一身份认证密码 / 校付宝支付密码 / 寝室） | App 直接用凭据访问学校系统，不走服务器，需设备在校园网 / 校内 VPN 内 |

服务器模式填任意地址即用（任意自建服务器皆可）；直连模式适合校内直连或自建服务器不可用时使用，验证码需手动输入。

## 功能

- **课程表**：多学期、周视图 / 日视图、下课即置灰；教务课表与考试安排导入；手动课程与日程事件（单次 / 每周重复），支持「仅本周」拆分；调休设置。服务器模式与网站共用同一份云端数据（最后写入胜），直连模式只存本机；未登录也可用本地功能。
- **成绩 / 学业情况 / 考试安排**：全部学期或按学期查询，平均绩点、学分绩点、各类别学分要求与课程明细。
- **学生评教**（插件 `evaluate`，原生界面）：直接复用已登录的教务会话，读出本轮待评列表；统一分数滑条 + 快捷档，逐条保存、全部打分、全部提交（提交不可撤销，写完回查教务确认）。
- **第二课堂**：达标分数、加分明细与活动看板，支持拼音搜索（全拼 / 首字母）与类别级联筛选；还能开「新活动提醒」——每小时后台检查一次，只在你选的大类 / 小类出现新活动时弹通知（「我的 → 配置」里设置）。
- **校园码 / 扫一扫**：30 秒刷新的动态付款码与余额，亮码期间常亮；扫一扫识别二维码（含相册识图、手电筒），可分流到第二课堂签到、拓展安装码与内置 WebView 打开网址。
- **宿舍电费**：余额、充值（防重复扣款）、7 / 30 / 90 天历史折线图。
- **抢课**（仅直连）：正方 9.0 选课轮次、余量与自动重试。
- **拓展与插件市场**：基于 **Cordis** 的运行时，一个拓展 = `ext.json` + `main.js`；`ctx.ui` / `storage` / `net` / `ai` / `notify` 等宿主服务，敏感权限在清单声明并在安装时展示。市场拓展分**依赖插件**（只暴露接口、不画界面）与**应用插件**（可创建一个或多个前端组件、也能用依赖插件的接口）；装应用插件会按**拓扑顺序**自动补齐依赖，过程用树状进度显示。插件市场从签名目录发现并安装拓展，也支持「添加第三方源」粘贴仓库名 + 核对公钥指纹。详见 [docs/extensions.md](docs/extensions.md)。
- **拓展工坊**：内置 Cordis 拓展，用自然语言让 Agent 写 / 改拓展；DSH Go 风格移动端 Agent 界面（流式输出、可折叠思考、计划模式 / 完全访问、多段对话、技能、一键发布到 GitHub / Gitee 并生成直装二维码）。
- **流体云课程通知**（插件 `course_cloud`，默认关闭）：课前 15 分钟常驻倒计时，ColorOS 流体云 / OriginOS 原子通知 / 澎湃OS 焦点通知按系统通知规则接入（Android 16+ 用 `ProgressStyle`），无需厂商 SDK；OPPO 官方卡片见 [oppo_card/README.md](oppo_card/README.md)。
- **桌面卡片与快捷方式**（插件 `home_widget`）：主屏「今日课程」与「校园卡余额」小部件 + 长按图标快捷方式，标准 AppWidget，各桌面通用。
- **备份与恢复**（插件 `backup`）：导出课表 / 设置 / 学校档案 / 插件偏好为 JSON，不含密码、登录态、AI Key、Cookie 与拓展数据。
- **界面**：悬浮玻璃顶栏、可预测式返回（Android 14+ 跟手返回）、工具卡片与拓展卡片长按整理（1×1 / 1×3 / 2×3 / 2×2 四档尺寸）、演示模式。
- **插件管理**：**一个插件 = 一个文件夹**（`packages/plugin_*`，一个文件夹可以贡献多个部件：底栏页 / 工具卡片 / 设置条目 / 主题色板 / AI 提供商），可逐项启停并查看依赖图。详见 [docs/plugins.md](docs/plugins.md) 与 [AGENTS.md](AGENTS.md)。

## 开发

仓库是一个 pub workspace：宿主 + `packages/campus_core`（契约层：服务、组件库、插件接口）+ 每功能 / 主题一个 `packages/plugin_*`（**一个插件 = 一个文件夹**，文件夹里可有多个部件）。动手前先看 [AGENTS.md](AGENTS.md)。

```bash
flutter pub get                     # 根目录一次解析全部包
dart run tool/gen_plugins.dart       # 改了插件依赖后重新生成清单 / 依赖表 / assets/plugin_folders.json
flutter test
flutter analyze
```

改插件集合（加包 / 删包）只动 `pubspec.yaml` 的依赖再跑生成器，清单不要手改。

### 构建

```bash
flutter pub get
flutter run                  # 连接设备 / 模拟器直接运行
flutter build apk --debug    # 或 --release
flutter build windows        # 需本机 Visual Studio 含 C++ 桌面开发工作负载
```

要求 Flutter 3.x 及以上。国内网络可配置 pub 镜像：`export PUB_HOSTED_URL=https://mirrors.cloud.tencent.com/dart-pub`。

### 发布签名

仓库**不含签名私钥**。本地构建从 `android/key.properties`（不进仓库，模板见 [android/key.properties.example](android/key.properties.example)）读取密钥，CI 从 Secrets 读 `RELEASE_KEYSTORE_BASE64` / `RELEASE_STORE_PASSWORD` / `RELEASE_KEY_ALIAS` / `RELEASE_KEY_PASSWORD` / `RELEASE_CERT_SHA1`；缺配置时 release 构建直接失败，不会产出不可安装的包。**换钥后旧版本无法覆盖安装**，老用户须卸载重装（本机数据会丢）。

### 发版

`pubspec.yaml` 升版本号 → 提交推送 → 打同名 tag（`git tag v1.0.4 && git push origin v1.0.4`），[release.yml](.github/workflows/release.yml) 会构建、校验签名指纹并发布 Release。

- 发布到 Gitee 与自建镜像：[tool/release_gitee.sh](tool/release_gitee.sh)（推代码 + tag + Release + APK）与 [tool/upload_mirror.sh](tool/upload_mirror.sh)（`anticraft.top/apk` 直链 + `latest.json` 兜底更新源）。
- Gitee Release 附件合计仅 1 GB，发版脚本会先跑 [tool/gitee_prune.py](tool/gitee_prune.py) 只保留最近 5 个版本（`GITEE_KEEP_VERSIONS` 可调），更老的 APK 删除——源码都在 git tag 里，更新链路只分发最新版。

### 调试：本地模拟校园服务（仅 debug 构建）

直连模式要访问学校内网，模拟器或校外环境连不上，「我的 → 连接设置 → 直连模式 → 使用本地模拟服务」可在 App 进程内（`127.0.0.1`）启动一套与学校系统行为一致的模拟服务，覆盖正方教务、金智统一认证 CAS、学工二课、校付宝四套协议，RSA / AES / SM4 都是真加解密。模拟凭据：学号 `25110001` / 统一认证 `sit@123456` / 支付密码 `888888` / 寝室 `24号楼1016`。release 构建不含模拟逻辑。

## 技术栈

- Flutter（Dart 3）、Material 3；本地持久化 `shared_preferences`；网络 `http` + JWT（401 单飞续期）
- 直连模式完整移植校园对接链路：正方教务（RSA + 图形验证码）、金智 CAS（AES-CBC）、校付宝（SM4），`pointycastle` 提供 AES / RSA
- 课表数据模型与网站 store 字段对齐，服务器模式可双向同步

## 隐私

- 仓库内不含任何真实个人信息、账号凭据或抓取数据
- **服务器模式**不存校园密码：凭据在服务器网站配置一次，由服务器加密保管
- **直连模式**的校园凭据明文保存在本机 `shared_preferences`，仅用于本机登录学校系统，不上传服务器；退出登录即清除密码并关闭自动重登
- **演示模式**使用本地假数据，不发起任何请求

## 自建服务器与协议

服务器模式可指向任意部署了同一套开放接口的服务器：

- 接口完整规约见 [docs/campus-api.md](docs/campus-api.md)（路径 / 请求响应结构 / 错误语义），可用任意语言、框架实现。
- 现成参考实现：[anticraft 校园服务网站](https://github.com/fromtheendtothebeginning/anticraft)，部署后把地址填进 App 即可。

## 开源协议

[GNU General Public License v3.0](LICENSE)（GPL-3.0）：可自由使用、学习、修改与再分发；再分发或衍生作品须同样以 GPL-3.0 开源并提供完整源码；软件不含任何担保。

抢课协议移植参考了 [zhengfang-apk](https://github.com/znjhahaha/zhengfang-apk)（GPL-3.0），解析与参数构造保留在 `packages/campus_core/lib/direct/course_select.dart` 并在文件头注明出处。

本项目为个人学习与自用工具，与任何学校官方无关；使用本软件产生的任何后果由使用者自行承担。