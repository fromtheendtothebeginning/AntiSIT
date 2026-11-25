import Code from "../components/Code.jsx";
import Icon from "../components/Icon.jsx";
import Reveal from "../components/Reveal.jsx";
import { SITE } from "../lib/site.js";

// 每章 = 一个纯函数组件；只渲染纯文本 + Code，不依赖任何外部状态，便于按需增删。
export default function DocContent({ id }) {
  const map = {
    overview: <Overview />,
    quickstart: <Quickstart />,
    structure: <Structure />,
    plugin: <WritePlugin />,
    manifest: <Manifest />,
    extension: <Extension />,
    "ext-publish": <ExtPublish />,
    api: <ApiSpec />,
    "self-host": <SelfHost />,
    release: <Release />,
    privacy: <Privacy />
  };
  return map[id] || map.overview;
}

const Rev = ({ children }) => <Reveal className="doc-section">{children}</Reveal>;

function Panel({ title, icon, children }) {
  return (
    <section className="panel">
      <div className="page-head" style={{ marginBottom: 12 }}>
        <h2 style={{ display: "flex", alignItems: "center", gap: 9 }}>
          {icon && (
            <span className="repo-icon" style={{ width: 30, height: 30, borderRadius: 10 }}>
              <Icon name={icon} size={15} />
            </span>
          )}
          {title}
        </h2>
      </div>
      <div className="doc-prose">{children}</div>
    </section>
  );
}

const QUICKSTART_SH = [
  "git clone https://gitee.com/ender123/AntiSIT.git",
  "cd AntiSIT",
  "flutter pub get",
  "",
  "# 国内网络可用 pub 镜像",
  "export PUB_HOSTED_URL=https://mirrors.cloud.tencent.com/dart-pub",
  "",
  "flutter run              # 连接设备 / 模拟器直接运行",
  "flutter test             # 全部测试（含插件包行为）",
  "flutter analyze          # CI 用 --fatal-infos，info 级 lint 也会红"
].join("\n");

const TREE = [
  "AntiXiaoYing/                     宿主 App：壳 / 设置 / 插件管理 / 清单组装",
  "  lib/main.dart                   组装注册表 + 注入主壳回调",
  "  lib/plugins/bootstrap.dart      buildAppRegistry()",
  "  lib/plugins/manifest.g.dart     <- 生成物，不要手改",
  "  lib/pages/{home,profile,plugin_manager}_page.dart",
  "  tool/gen_plugins.dart           清单 + 依赖表生成器（含依赖校验）",
  "  packages/",
  "    campus_core/                  契约层：服务 + 组件库 + 插件接口 + 能力接口",
  "    plugin_timetable/  plugin_ecard/  plugin_grades/  plugin_exams/",
  "    plugin_score/      plugin_activities/  plugin_electricity/",
  "    plugin_ext/        plugin_webview/     plugin_camera/  plugin_scan/",
  "    plugin_ai_*/       <- AI 提供商：一家一个包（含自家 logo）",
  "    plugin_theme_glass/  plugin_theme_ink/  plugin_theme_bamboo/"
].join("\n");

const PKG_YAML = [
  "dependencies:",
  "  campus_core:",
  "    path: ../campus_core"
].join("\n");

const HOST_DART = [
  "// 契约层只向下依赖，宿主把实现注入进来",
  'Widget Function() hostShellBuilder = () => const SizedBox.shrink();'
].join("\n");

const EXT_JSON = [
  "{",
  '  "id": "sit.my-tool",',
  '  "name": "我的工具",',
  '  "version": "1.0.0",',
  '  "permissions": ["storage", "network"],',
  '  "main": "main.js"',
  "}"
].join("\n");

const EXT_JS = [
  "export default function () {",
  "  return {",
  "    inject: ['ui', 'storage'],",
  "    apply(ctx) {",
  "      ctx.ui.push(() => ctx.ui.h('div', '你好'));",
  "      ctx.effect(() => ctx.storage.set('seen', Date.now()));",
  "    }",
  "  };",
  "}"
].join("\n");

const INSTALL_CODE = [
  "{",
  '  "antisit": "ext",',
  '  "url": "https://example.com/sit.my-tool.zip",',
  '  "sha256": "64 位十六进制",',
  '  "name": "可选，仅安装前展示",',
  '  "id": "可选；写了必须与包内 ext.json 一致"',
  "}"
].join("\n");

const LOGIN_HTTP = [
  "POST /api/login",
  "Content-Type: application/json",
  "",
  '{ "username": "demo", "password": "***" }',
  "",
  "200 -> {",
  '  "access_token": "<令牌>",',
  '  "token_type": "bearer",',
  '  "user": { "id": 126, "username": "demo", "role": "user" }',
  "}"
].join("\n");

const HEALTH_SH = [
  "# 服务器起来之后先用健康检查探一下",
  "curl https://your-host/api/health",
  '# -> {"status":"ok","message":"anticraft API is running"}'
].join("\n");

const RELEASE_SH = [
  "# 1) 改 pubspec.yaml 的 version（如 1.48.0+205）",
  'git commit -am "release 1.48.0"',
  "git push",
  "",
  "# 2) 打同名 tag，触发 .github/workflows/release.yml",
  "git tag v1.48.0",
  "git push origin v1.48.0",
  "",
  "# 3) 同步 Gitee（代码 + tag + Release + APK）",
  "tool/release_gitee.sh",
  "",
  "# 4) 推自建镜像（直链 + latest.json 兜底更新源）",
  "tool/upload_mirror.sh"
].join("\n");

function Overview() {
  return (
    <Rev>
      <Panel title="项目总览" icon="book">
        <p>
          {SITE.name} 是一个 pub workspace：宿主 App（壳、设置、插件管理、清单组装）+ 契约层
          <span className="mono"> campus_core </span> + 每个功能 / 主题 / AI 提供商各一个
          <span className="mono"> plugin_*</span> 包。
        </p>
        <div className="kv">
          <div className="kv-k">技术栈</div>
          <div className="kv-v">Flutter 3（Dart 3）、Material 3；本地持久化 shared_preferences；网络 http + JWT 鉴权。</div>
        </div>
        <div className="kv">
          <div className="kv-k">直连模式</div>
          <div className="kv-v">正方教务（RSA 密码 + 图形验证码）、金智统一认证 CAS（AES-CBC）、校付宝（SM4）；pointycastle 提供 AES / RSA，SM4 为纯 Dart 实现。</div>
        </div>
        <div className="kv">
          <div className="kv-k">拓展运行时</div>
          <div className="kv-v">Cordis（DSH 同款插件框架）。一个拓展 = ext.json + main.js，在 WebView 里跑，通过 ctx 拿宿主服务。</div>
        </div>
        <div className="kv">
          <div className="kv-k">许可</div>
          <div className="kv-v">GPL-3.0。允许商业使用、修改、再分发，衍生作品须同样以 GPL-3.0 开源并提供源码。</div>
        </div>
        <p style={{ marginTop: 14 }}>
          仓库同时镜像在 GitHub 与 Gitee：GitHub 跑 CI 构建并发布 Release，Gitee 用于国内直连下载，
          自建镜像 <span className="mono">{SITE.host}/apk</span> 作为 App 内更新源的兜底。
        </p>
      </Panel>
    </Rev>
  );
}

function Quickstart() {
  return (
    <Rev>
      <Panel title="本地跑起来" icon="code">
        <p>需要 Flutter 3 及以上。仓库是 workspace，根目录一次解析就能拿到所有包：</p>
        <Code title="bash" badge="~30s" text={QUICKSTART_SH}>{QUICKSTART_SH}</Code>
        <p>
          Windows 端没有现成安装包：CI 只发 Android APK，Windows 请自行
          <span className="mono"> flutter build windows </span>
          （需 Visual Studio 含 C++ 桌面开发工作负载）。
        </p>
        <div className="kv">
          <div className="kv-k">发布签名</div>
          <div className="kv-v">仓库不含私钥。构建从 <span className="mono">android/key.properties</span>（不进库，模板见 .example）或环境变量读密钥；缺配置时 release 构建直接失败，绝不产出装不上的包。</div>
        </div>
        <div className="kv">
          <div className="kv-k">演示模式</div>
          <div className="kv-v">内置本地假数据，无需账号即可把全部界面点一遍；不会发起任何请求。</div>
        </div>
      </Panel>
    </Rev>
  );
}

function Structure() {
  return (
    <Rev>
      <Panel title="仓库结构" icon="list">
        <Code title="tree" badge="workspace" text={TREE}>{TREE}</Code>
        <p>
          所有包在同一个 pub workspace 里（根 pubspec 的 <span className="mono">workspace:</span> + 各包
          <span className="mono"> resolution: workspace</span>），根目录一次
          <span className="mono"> flutter pub get</span> 全部解析。
        </p>
        <Code title="yaml" badge="包内" text={PKG_YAML}>{PKG_YAML}</Code>
      </Panel>
    </Rev>
  );
}

function WritePlugin() {
  return (
    <Rev>
      <Panel title="写一个功能插件" icon="puzzle">
        <p>
          一个插件 = 一个 Dart 包。它通过重写贡献方法交出底栏页面、工具卡片或设置条目，并通过
          <span className="mono"> id / dependencies / optionalDependencies / removable </span>
          声明自己是谁、依赖谁。
        </p>
        <div className="kv">
          <div className="kv-k">硬依赖</div>
          <div className="kv-v">启停联动：启用我时一起启用；停用被依赖者会连带停用我。关系图画实线。</div>
        </div>
        <div className="kv">
          <div className="kv-k">软依赖</div>
          <div className="kv-v">可选增强：不联动，虚线。能力接口（camera / scan / webview / reminder）就是插件软用另一个插件的常见形式。</div>
        </div>
        <div className="kv">
          <div className="kv-k">往上跳</div>
          <div className="kv-v">插件不能引用宿主页面（会成环）。登录成功回主壳这类需求改成宿主在 main() 里注入的回调。</div>
        </div>
        <Code title="dart" badge="campus_core/host.dart" text={HOST_DART}>{HOST_DART}</Code>
        <p>
          接第三方能力（AI / 摄像头 / 分享）前，先在官网核对接口形式；官网与实测冲突时以实测为准，
          并在 PR 描述里写清理由。
        </p>
      </Panel>
    </Rev>
  );
}

function Manifest() {
  return (
    <Rev>
      <Panel title="清单与依赖生成" icon="widget">
        <p>
          插件清单（<span className="mono">lib/plugins/manifest.g.dart</span>）与依赖关系表都由脚本扫描各包源码生成。
          加插件时忘了写依赖，新插件会以「无依赖」出现在表里，一眼能看出来。
        </p>
        <Code title="bash" text={"# 改了插件依赖后重新生成清单\ndart run tool/gen_plugins.dart"}>
          {"# 改了插件依赖后重新生成清单\ndart run tool/gen_plugins.dart"}
        </Code>
        <p>
          生成器会直接报错退出（不用等运行期才在管理页看到告警）的条件：依赖引用了不存在的 id、自依赖、
          硬依赖成环。
        </p>
        <div className="kv">
          <div className="kv-k">加一个插件</div>
          <div className="kv-v">新建包 → 在根 pubspec 的 workspace 列表加一行 → 需要时登册 → 跑生成器 → 跑 analyze。</div>
        </div>
        <div className="kv">
          <div className="kv-k">删一个插件</div>
          <div className="kv-v">去掉依赖那一行再跑生成器；包目录可留可删。构建期还能用 --dart-define=EXCLUDE_XXX=true 剔除。</div>
        </div>
      </Panel>
    </Rev>
  );
}

function Extension() {
  return (
    <Rev>
      <Panel title="Cordis 拓展开发" icon="code">
        <p>
          一个拓展就是在 WebView 里运行的 Cordis 插件：通过 <span className="mono">inject</span> 声明要用的服务，
          用 <span className="mono">ctx.effect()</span> 注册可逆副作用。压缩包根目录放
          <span className="mono"> ext.json + main.js </span>（可选 <span className="mono">style.css</span>）。
        </p>
        <Code title="json" badge="ext.json" text={EXT_JSON}>{EXT_JSON}</Code>
        <Code title="js" badge="main.js" text={EXT_JS}>{EXT_JS}</Code>
        <div className="kv">
          <div className="kv-k">敏感权限</div>
          <div className="kv-v">storage / network / ai / notification 必须在清单声明；校内明文 http 的教学站点用单独一条 campus_net（服务器模式下自动走校园隧道代理）。</div>
        </div>
        <div className="kv">
          <div className="kv-k">旧包</div>
          <div className="kv-v">旧 html 压缩包标为「旧版网页拓展（需迁移）」；网址型书签照旧可用。</div>
        </div>
      </Panel>
    </Rev>
  );
}

function ExtPublish() {
  return (
    <Rev>
      <Panel title="拓展市场与第三方源" icon="shield">
        <p>
          市场目录必须过签名校验：公钥内置 App，私钥只在维护者本机 —— 所以目录可以随便挂镜像，
          镜像改不了内容。每个拓展包还要对得上 sha256 才解压。
        </p>
        <p>
          不需要官方收录也能发：作者在自己仓库用同一套工具签名打包，别人在「添加第三方源」里粘贴
          仓库名 + 核对公钥指纹即可安装；第三方条目明确标注「未审核」，同一个 id 只能由一个源管。
        </p>
        <Code title="json" badge="安装码" text={INSTALL_CODE}>{INSTALL_CODE}</Code>
        <div className="kv">
          <div className="kv-k">安装校验</div>
          <div className="kv-v">只认 https 且必须带 sha256；下载后先核对内容，对不上连解压都不做。通过后才把包里的名称 / id / 版本 / 权限列给用户确认。</div>
        </div>
        <div className="kv">
          <div className="kv-k">更新与卸载</div>
          <div className="kv-v">更新保留拓展自己的数据，卸载一并清掉。</div>
        </div>
      </Panel>
    </Rev>
  );
}

function ApiSpec() {
  return (
    <Rev>
      <Panel title="开放接口规约" icon="code">
        <p>
          只看规约就能用任意语言实现出相同接口形式的客户端或服务端：路径、方法、请求 / 响应结构、
          状态码、错误语义一致。服务端内部机制（密码存储、令牌签发）与上游学校系统对接不在规约范围。
        </p>
        <Code title="http" badge="鉴权" text={LOGIN_HTTP}>{LOGIN_HTTP}</Code>
        <div className="kv">
          <div className="kv-k">鉴权头</div>
          <div className="kv-v">Authorization: Bearer &lt;access_token&gt;</div>
        </div>
        <div className="kv">
          <div className="kv-k">成功字段</div>
          <div className="kv-v">各接口自定义，但均含 "ok": true（登录 / 续期除外）。</div>
        </div>
        <div className="kv">
          <div className="kv-k">错误</div>
          <div className="kv-v">{'统一 {"detail":"<中文说明>"}；422 校验错误时 detail 是数组，loc 指明字段路径。'}</div>
        </div>
        <div className="kv">
          <div className="kv-k">限流</div>
          <div className="kv-v">{'按客户端 IP 计数，超限统一 429 {"detail":"请求过于频繁，请稍后再试"}。'}</div>
        </div>
        <div className="kv">
          <div className="kv-k">健康检查</div>
          <div className="kv-v">{'GET /api/health（免鉴权）-> {"status":"ok","message":"...running"}'}</div>
        </div>
        <p>
          完整规约（含每个接口字段与错误文案对照）在仓库
          <a className="mono" href={SITE.repos.github.url + "/blob/main/docs/campus-api.md"} target="_blank" rel="noreferrer">
            {" docs/campus-api.md "}
          </a>
          。
        </p>
      </Panel>
    </Rev>
  );
}

function SelfHost() {
  return (
    <Rev>
      <Panel title="自建服务器" icon="shield">
        <p>
          服务器模式的地址可以是任意部署了同一套开放接口的服务器（<span className="mono">IP:端口</span> 或域名）。
          客户端不写死域名，所以自建服务器对 App 完全等价于官方服务器。
        </p>
        <Code title="bash" badge="自检" text={HEALTH_SH}>{HEALTH_SH}</Code>
        <div className="kv">
          <div className="kv-k">必须实现</div>
          <div className="kv-v">/api/login、令牌续期、/api/campus-open 下客户端用到的路径；错误响应统一 detail 语义。</div>
        </div>
        <div className="kv">
          <div className="kv-k">不必实现</div>
          <div className="kv-v">站点的网页功能（奖学金评定等）与 App 无关；App 只依赖接口形式。</div>
        </div>
        <div className="kv">
          <div className="kv-k">HTTPS</div>
          <div className="kv-v">生产环境请上 TLS：下载更新只接受发布域及其 CDN 的 https 链接。</div>
        </div>
      </Panel>
    </Rev>
  );
}

function Release() {
  return (
    <Rev>
      <Panel title="发版流程" icon="download">
        <p>
          升版本号 → 提交推送 → 打同名 tag，CI 会构建、校验签名指纹并发布 Release；再把代码与 Release
          同步到 Gitee，并把 APK 推到自建镜像。
        </p>
        <Code title="bash" text={RELEASE_SH}>{RELEASE_SH}</Code>
        <div className="kv">
          <div className="kv-k">校验文件</div>
          <div className="kv-v">每个 APK 都带 .apk.sha256。App 只在拿到并通过校验文件后才交给系统安装器。</div>
        </div>
        <div className="kv">
          <div className="kv-k">Gitee 配额</div>
          <div className="kv-v">Release 附件合计 1 GB，每版 APK 约 87 MB —— 发版脚本会按版本号保留最近 5 个，更老的删掉（源码都在 git tag 里）。</div>
        </div>
        <div className="kv">
          <div className="kv-k">签名一致</div>
          <div className="kv-v">同一把发布密钥签名的版本可直接覆盖安装并保留数据；换签名必须先卸载。</div>
        </div>
      </Panel>
    </Rev>
  );
}

function Privacy() {
  return (
    <Rev>
      <Panel title="隐私与凭据" icon="shield">
        <p>仓库内不含任何真实个人信息、账号凭据、接口凭据或抓取数据。</p>
        <div className="kv">
          <div className="kv-k">服务器模式</div>
          <div className="kv-v">不存校园密码。校园凭据在服务器网站配置一次，由服务器加密保管，App 全程不接触。</div>
        </div>
        <div className="kv">
          <div className="kv-k">直连模式</div>
          <div className="kv-v">校园凭据明文保存在本机 shared_preferences，仅用于本机直接登录学校系统，不上传任何服务器；退出登录即清除密码。</div>
        </div>
        <div className="kv">
          <div className="kv-k">退出登录</div>
          <div className="kv-v">手动退出是明确的「我要下线」信号：token、保存的账号密码、校园密码一起清掉，并把「记住密码并自动重登」关掉。</div>
        </div>
        <div className="kv">
          <div className="kv-k">本地仅存</div>
          <div className="kv-v">登录 token、课表数据、界面设置、直连模式 Cookie；「我的」页可一键清除会话。</div>
        </div>
        <div className="kv">
          <div className="kv-k">本站</div>
          <div className="kv-v">这个站点是纯静态页面：没有埋点、没有 Cookie、没有后端接口调用（唯一下载的是公开的版本信息文件）。</div>
        </div>
      </Panel>
    </Rev>
  );
}
