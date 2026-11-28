// 拓展工坊：内置 Cordis 拓展。
//
// 这里是一个轻量版的 DSH Agent 内核：
// * Session 是 append-only 事件日志，模型请求从日志派生；
// * turn / step 两层循环，turn 结束才回到 idle；
// * inbox 支持运行中插话（下一步 claim）；
// * 工具注册表 + 批量执行 + 读后写版本校验；
// * 崩溃后修复未闭合的 turn 和没有结果的 tool call。
//
// 页面只负责渲染事件日志，不再维护另一份 messages/history。

const MAX_STEPS = 40;
const MAX_EVENTS = 400;
const MAX_TOOL_RESULT_CHARS = 24000;
const MAX_READ_LINES = 2000;
const DEFAULT_READ_LINES = 400;
const MAX_READ_CHARS = 20000;
const MAX_SESSION_BYTES = 1800000;
const SESSION_ENCODER = new TextEncoder();

// 单页单实例：工具与 Agent 循环都需要访问同一份宿主服务与页面状态。
let S = null;
let ctx = null;
let notify = () => {};
let onSessionChange = () => {};


// 描边图标（内联 SVG，跟 DSH 一样不依赖图标字体）。
const ICONS = {
  mic: '<svg viewBox="0 0 24 24"><path d="M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3z"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/><path d="M9 21h6"/></svg>',
  stop: '<svg viewBox="0 0 24 24"><rect x="7" y="7" width="10" height="10" rx="2"/></svg>',
  send: '<svg viewBox="0 0 24 24"><path d="M12 19V6"/><path d="M6.5 11.5L12 6l5.5 5.5"/></svg>',
  menu: '<svg viewBox="0 0 24 24"><path d="M4 7h16"/><path d="M4 12h16"/><path d="M4 17h16"/></svg>',
  more: '<svg viewBox="0 0 24 24"><circle cx="6" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="18" cy="12" r="1.4"/></svg>',
};

// 「/」面板里给工具看的**中文**名字与一句说明：工具本身的 description 是写
// 给模型看的英文，直接摆到面板上就是「界面里还混着英文」。
const TOOL_UI_LABELS = {
  set_goal: ['设定目标', '这条对话要达成什么'],
  update_plan: ['更新计划', '列出步骤与进度'],
  mcp_list_tools: ['MCP 工具列表', '看接入的服务器有哪些工具'],
  mcp_call: ['调用 MCP 工具', '用一台服务器上的某个工具'],
  list_files: ['看文件', '列出这个拓展的文件'],
  read_file: ['读文件', '读一个文本文件的内容'],
  write_file: ['写文件', '新建或整体覆盖一个文件'],
  edit_file: ['改文件', '按原文替换一小段'],
  delete_file: ['删文件', '删掉一个文件'],
  validate_extension: ['自检', '检查清单、入口与常见写法问题'],
  preview_extension: ['预览', '用当前草稿打开预览'],
  install_extension: ['安装', '把草稿装进拓展列表'],
  list_skills: ['技能列表', '看已安装的技能'],
  read_skill: ['读技能', '读一条技能的完整说明'],
  install_skill: ['存技能', '把一段方法论存进技能库'],
  delete_skill: ['删技能', '删掉一条技能'],
};
const WELCOME = `
  <div class="welcome">
    <div class="welcome-mark"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l7 4v10l-7 4-7-4V7z"/></svg></div>
    <div class="welcome-title">今天做点什么</div>
    <div class="welcome-note">说清楚要的小工具，它会先看拓展、读文件、再改；写文件和安装前默认会弹确认。运行中也能继续插话。输入 <code>/</code> 可以直接调用工具或技能。</div>
    <div class="welcome-grid">
      <button class="welcome-card" data-say="做一个记录喝水次数的小工具，数据要留在本机">
        <strong>喝水记录</strong><span>本机存数据，点一下就加一次</span>
      </button>
      <button class="welcome-card" data-say="做一个用 AI 总结文本文件的工具：可以选择文件、显示摘要，还能把摘要保存成 txt">
        <strong>AI 总结文件</strong><span>选文件、看摘要、存成 txt</span>
      </button>
      <button class="welcome-card" data-say="做一个倒计时，可以设定目标日期">
        <strong>倒计时</strong><span>设定目标日期，显示还剩几天</span>
      </button>
      <button class="welcome-card" data-say="先读一下当前 main.js，告诉我它是做什么的">
        <strong>读懂当前拓展</strong><span>先读 main.js，讲清它在干什么</span>
      </button>
    </div>
    <div class="welcome-slash">输入 <code>/</code> 调用工具与技能</div>
  </div>`;

// ==================== 会话日志 ====================

class AgentSession {
  constructor(vault, draftId, conversationId, onChange) {
    this.vault = vault;
    this.draftId = draftId;
    this.conversationId = conversationId || 'default';
    this.title = '新对话';
    this.createdAt = Date.now();
    this.updatedAt = this.createdAt;
    this.onChange = onChange;
    this.events = [];
    this.seq = 0;
    this.turnSeq = 0;
    this.observed = new Map();
    // 目标 / 计划：都是会话级状态（不是聊天消息），从事件流里重建
    this.goal = '';
    this.plan = [];
    this.dirty = false;
    this.timer = null;
    this.saving = null;
  }

  static async load(vault, draftId, conversationId, onChange) {
    const session = new AgentSession(vault, draftId, conversationId, onChange);
    let raw = null;
    try {
      raw = await vault.loadSession(draftId, session.conversationId);
    } catch (e) {
      console.warn('[workshop] 会话日志读取失败，按新会话处理', e);
    }
    if (raw) {
      try {
        const data = JSON.parse(raw);
        if (data && Array.isArray(data.events)) {
          session.events = data.events.filter((e) => e && typeof e.type === 'string');
          session.seq = Number(data.seq) || 0;
          session.turnSeq = Number(data.turnSeq) || 0;
          session.title = String(data.title || '') || session.title;
          session.createdAt = Number(data.createdAt) || session.createdAt;
          session.updatedAt = Number(data.updatedAt) || session.updatedAt;
        }
      } catch (e) {
        console.warn('[workshop] 会话日志损坏，按新会话处理', e);
      }
    }
    session.rebuildState();
    session.repair();
    return session;
  }

  append(type, data) {
    const event = Object.assign({ seq: ++this.seq, type: type }, data || {});
    this.events.push(event);
    this.updatedAt = Date.now();
    // 第一条用户消息当作对话标题（列表里显示），太长就截断
    if (type === 'user/message' && data && data.source === 'user') {
      const text = String(data.content || '').replace(/\s+/g, ' ').trim();
      if (text && (!this.title || this.title === '新对话')) {
        this.title = text.slice(0, 24);
      }
    }
    this.observeEvent(event);
    this.prune();
    this.scheduleSave();
    if (this.onChange) this.onChange();
    return event;
  }

  nextTurn() {
    this.turnSeq += 1;
    return this.turnSeq;
  }

  rebuildState() {
    this.observed = new Map();
    this.goal = '';
    this.plan = [];
    this.turnSeq = 0;
    for (const event of this.events) {
      if (event.seq > this.seq) this.seq = event.seq;
      if (event.type === 'turn/start' && event.turn > this.turnSeq) {
        this.turnSeq = event.turn;
      }
      this.observeEvent(event);
    }
  }

  observeEvent(event) {
    if (event.type === 'goal/set') {
      this.goal = String(event.objective || '');
    } else if (event.type === 'plan/update') {
      this.plan = Array.isArray(event.steps)
        ? event.steps.map((s) => ({
            content: String((s && s.content) || ''),
            status: ['pending', 'in_progress', 'completed'].includes(s && s.status)
              ? s.status
              : 'pending',
          }))
        : [];
    } else if (event.type === 'file/observed') {
      this.observed.set(event.path, event.version || '');
    } else if (event.type === 'file/removed') {
      this.observed.delete(event.path);
    }
  }

  observe(path, version) {
    const value = version || '';
    if (this.observed.get(path) === value) return;
    this.observeEvent({ type: 'file/observed', path: path, version: value });
    this.observed.set(path, value);
    this.append('file/observed', { path: path, version: value });
  }

  forget(path) {
    this.observed.delete(path);
    this.append('file/removed', { path: path });
  }

  /** 修复上次崩溃留下的未闭合 turn 和没有结果的 tool call。 */
  repair() {
    const openTurns = new Set();
    for (const event of this.events) {
      if (event.type === 'turn/start') openTurns.add(event.turn);
      else if (event.type === 'turn/end') openTurns.delete(event.turn);
    }
    const assistants = this.events.filter((e) => e.type === 'assistant/message');
    for (const message of assistants) {
      const calls = Array.isArray(message.toolCalls) ? message.toolCalls : [];
      for (const call of calls) {
        if (!call || !call.id) continue;
        if (this.events.some((e) => e.type === 'tool/result' && e.callId === call.id)) continue;
        const started = this.events.some((e) => e.type === 'tool/call' && e.callId === call.id);
        this.append('tool/result', {
          turn: message.turn,
          step: message.step,
          callId: call.id,
          name: call.name,
          isError: true,
          recovered: true,
          content: started
            ? 'Error: tool call outcome is unknown. Its result was not recorded; check the workspace before retrying.'
            : 'Error: tool call was interrupted before it started. Retry it if it is still needed.',
        });
      }
    }
    for (const turn of openTurns) {
      this.append('turn/end', { turn: turn, reason: { kind: 'aborted', reason: { kind: 'interrupted' } } });
    }
    if (openTurns.size > 0) {
      this.append('error', { text: '上次运行被中断，已恢复会话；可以继续发消息。' });
    }
  }

  /** 轻量压缩：只按完整 turn 丢最旧的一段，避免把 tool call / result 拆散。 */
  prune() {
    while (this.events.length > MAX_EVENTS) {
      let end = -1;
      for (let i = 0; i < this.events.length; i++) {
        if (this.events[i].type === 'turn/end') {
          end = i;
          break;
        }
      }
      if (end < 0) break;
      this.events.splice(0, end + 1);
    }
  }

  scheduleSave() {
    this.dirty = true;
    if (this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      this.flush();
    }, 250);
  }

  async flush() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    if (this.saving) {
      await this.saving.catch(() => {});
    }
    if (!this.dirty) return;
    this.dirty = false;
    this.saving = this.save();
    try {
      await this.saving;
    } finally {
      this.saving = null;
    }
  }

  async save() {
    let payload = this.serialize();
    while (SESSION_ENCODER.encode(payload).length > MAX_SESSION_BYTES) {
      let end = -1;
      for (let i = 0; i < this.events.length; i++) {
        if (this.events[i].type === 'turn/end') {
          end = i;
          break;
        }
      }
      if (end < 0) break;
      this.events.splice(0, end + 1);
      payload = this.serialize();
    }
    try {
      await this.vault.saveSession(this.draftId, this.conversationId, payload);
    } catch (e) {
      this.dirty = true;
      console.warn('[workshop] 会话日志保存失败', e);
    }
  }

  serialize() {
    return JSON.stringify({
      version: 1,
      draftId: this.draftId,
      conversationId: this.conversationId,
      title: this.title,
      createdAt: this.createdAt,
      updatedAt: this.updatedAt,
      seq: this.seq,
      turnSeq: this.turnSeq,
      events: this.events,
    });
  }

  /** 从日志派生模型消息：最新 system、user/context、assistant、tool。 */
  deriveMessages() {
    const messages = [];
    let system = '';
    for (const event of this.events) {
      if (event.type === 'system/message' && event.text) system = event.text;
    }
    if (system) messages.push({ role: 'system', content: system });
    for (const event of this.events) {
      if (event.type === 'user/message' || event.type === 'context/message') {
        messages.push({ role: 'user', content: event.content || '' });
      } else if (event.type === 'assistant/message') {
        const calls = Array.isArray(event.toolCalls) ? event.toolCalls : [];
        messages.push({
          role: 'assistant',
          content: event.text || '',
          toolCalls: calls,
        });
      } else if (event.type === 'tool/result' && !event.textProtocol) {
        messages.push({
          role: 'tool',
          content: event.content || '',
          toolCallId: event.callId || '',
        });
      }
    }
    return messages;
  }

  /** 给 UI 的投影：只保留聊天里要显示的事件。 */
  projectChat() {
    const out = [];
    const calls = new Map();
    for (const event of this.events) {
      if (event.type === 'goal/set') {
        const objective = String(event.objective || '').trim();
        if (objective) out.push({ role: 'goal', text: objective, key: 'g' + event.seq });
      } else if (event.type === 'plan/update') {
        const steps = Array.isArray(event.steps) ? event.steps : [];
        // 后来更新的覆盖前面那条：同一个计划只显示最新一版
        const last = out.length ? out[out.length - 1] : null;
        if (last && last.role === 'plan') out.pop();
        if (steps.length) out.push({ role: 'plan', steps: steps.slice(), key: 'p' + event.seq });
      } else if (event.type === 'user/message') {
        if (event.source === 'user') out.push({ role: 'user', text: event.content || '' });
      } else if (event.type === 'assistant/message') {
        if (!event.hidden && (event.text || event.reasoning)) {
          out.push({
            role: 'assistant',
            text: event.text || '',
            reasoning: event.reasoning || '',
            key: 'a' + event.seq,
          });
        }
      } else if (event.type === 'tool/call') {
        const card = {
          role: 'tool',
          name: event.name || 'tool',
          args: event.arguments || '',
          result: '',
          ok: true,
          running: true,
          key: 't' + (event.callId || event.seq),
        };
        out.push(card);
        calls.set(event.callId, card);
      } else if (event.type === 'tool/result') {
        const card = calls.get(event.callId);
        if (card) {
          card.result = event.content || '';
          card.ok = !event.isError;
          card.running = false;
        } else {
          out.push({
            role: 'tool',
            name: event.name || 'tool',
            args: '',
            result: event.content || '',
            ok: !event.isError,
            running: false,
            key: 't' + (event.callId || event.seq),
          });
        }
      } else if (event.type === 'error' && !event.hidden) {
        out.push({ role: 'error', text: event.text || '', key: 'e' + event.seq });
      }
    }
    return out;
  }

  hasVisibleMessages() {
    return this.events.some((e) =>
      e.type === 'user/message' && e.source === 'user'
      || e.type === 'assistant/message' && (e.text || e.reasoning) && !e.hidden
      || e.type === 'tool/call'
      || e.type === 'error' && !e.hidden);
  }
}

// ==================== inbox ====================

class Inbox {
  constructor() {
    this.nextTurn = [];
    this.nextStep = [];
  }

  push(target, message) {
    if (target === 'next-step') this.nextStep.push(message);
    else this.nextTurn.push(message);
  }

  claimTurn() {
    const out = this.nextTurn.splice(0).concat(this.nextStep.splice(0));
    return out;
  }

  claimStep() {
    return this.nextStep.splice(0);
  }

  hasPending() {
    return this.nextTurn.length > 0 || this.nextStep.length > 0;
  }

  clear() {
    this.nextTurn.length = 0;
    this.nextStep.length = 0;
  }
}

// ==================== 系统提示词分段 ====================

const PROMPT_SECTIONS = [
  {
    name: 'identity',
    order: 0,
    text: 'You are AntiSIT Workshop, a coding agent running inside the AntiSIT Android app. You build Cordis extensions for this app.',
  },
  {
    name: 'workflow',
    order: 100,
    text: [
      '## How you work',
      '- Look before you change: use list_files and read_file. Never overwrite a file you have not read in this session.',
      '- Prefer edit_file for targeted changes; write_file only creates a file or replaces the whole file.',
      '- After changing code, call validate_extension and fix every reported problem.',
      '- Call install_extension only when the user explicitly asks to install. Writes, deletes and installs are confirmed by the app.',
      '- Reply in Chinese, concisely. Do not paste whole files unless the user asks.',
    ].join('\n'),
  },
  {
    name: 'goal-and-plan',
    order: 140,
    text: () => {
      const goal = (S && S.session && S.session.goal) || '';
      const plan = (S && S.session && S.session.plan) || [];
      const lines = [
        '## Goal and plan',
        goal
          ? 'Current goal: ' + goal
          : 'No goal set. Call set_goal before multi-step work so the user can see what you are doing.',
        plan.length
          ? 'Current plan:\n' + plan
              .map((s, i) => (i + 1) + '. [' + s.status + '] ' + s.content)
              .join('\n')
          : 'No plan yet. Use update_plan for anything that takes more than two steps, and keep it current.',
        'Both are visible to the user as cards in the chat, so keep them short and truthful.',
      ];
      return lines.join('\n');
    },
  },
  {
    name: 'plan-mode',
    order: 150,
    text: () => S && S.planMode ? [
      '## Plan mode (ON)',
      'You are in PLAN MODE. Use only read-only tools to investigate. Do not write, edit, delete, install, preview, or install skills.',
      'When you have enough context, reply with a concrete plan: ordered steps, files to change, exact changes, and how to validate. Do not claim anything was changed.',
      'The user can turn plan mode off and ask you to execute the plan.',
    ].join('\n') : '',
  },
  {
    name: 'skills',
    order: 350,
    text: () => {
      const skills = (S && S.skills) || [];
      return [
        '## Skills',
        skills.length
          ? 'Installed skills (progressive disclosure). Read one with read_skill when it matches the task:'
          : 'No skills installed yet.',
        ...skills.map((s) => '- ' + s.name + ': ' + (s.description || '（无说明）')),
        'A skill is a reusable instruction document, not executable code. Use install_skill to save one for future tasks; it asks the user (unless full access is on).',
      ].join('\n');
    },
  },
  {
    name: 'tool-guidance',
    order: 200,
    text: () => [
      '## Tools',
      ...availableTools().map((tool) => '- ' + tool.name + ': ' + tool.prompt),
      'Tool failures are real failures. Read the error and correct the call; never claim success.',
    ].join('\n'),
  },
  {
    name: 'extension-format',
    order: 300,
    text: [
      '## Extension format',
      'A draft directory has ext.json and main.js, plus optional style.css.',
      'ext.json example:',
      '{"id":"sit.my-tool","name":"我的工具","desc":"一句话","version":"0.1.0","main":"main.js","style":"style.css","permissions":["storage"]}',
      '',
      'main.js must export default a Cordis plugin (function or object with apply):',
      'export default { name: "my-tool", inject: ["ui"], apply(ctx) { ctx.ui.root.appendChild(AntiUI.page({ title: "你好", children: [AntiUI.card({ title: "开始吧" })] })); } };',
      '',
      'Available services after declaring them in inject:',
      '- ctx.ui: root, toast(text), close(), theme, onThemeChange(fn), push({onPop}) (returns {root, close}), pop(), depth, canGoBack (page stack; system back pops it first), kit (= AntiUI), confirm(options), sheet(options)',
      '- Theme / dark mode: the host injects the native palette as CSS variables (--antisit-bg, --antisit-card, --antisit-menu-bg, --antisit-input-fill, --antisit-gold, --antisit-on-accent, --antisit-overlay, --antisit-wells, radius-*). AntiUI consumes them, so Theme switching is automatic. ctx.ui.theme carries the same values for canvas/chart use; ctx.ui.onThemeChange(fn) fires on theme or dark-mode changes. Never hard-code light/dark colors.',
      '- AntiUI (global): the app-styled component kit. Use it before writing your own CSS. Builders: page({title, subtitle, children}), card({title, desc, children, actions, onClick}), button(label, {variant, icon, block, onClick}), list([row]), row({title, desc, icon, side, chevron, onClick}), switchRow({title, desc, checked, onChange}), field/input/textarea, segmented({items, index, onChange}), chips(items, {value, onChange}), topbar({title, subtitle, onBack, actions}), empty({icon, title, desc, action}), spinner(), loading(text), progress(value), sheet({title, desc, content, actions}), confirm({title, text, confirmText, danger}), actions({title, items}), toast(text), copy(text), formatBytes(n). Icons: back, chevron, close, check, plus, search, file, folder, download, upload, trash, info, refresh, copy, send, sparkles, link, clock, more.',
      '- ctx.storage: get/set/remove(key), Promise-based, isolated by extension id',
      '- ctx.card: setName/setDesc/setIcon',
      '- ctx.ai: chat(prompt, {system, maxTokens})',
      '- ctx.notify: show({title, body, key, popup?}), popup({title, body, key}), schedule({key, title, body, at, popup?}), cancel(key), cancelAll() — requires the notification permission; popup uses a high-importance channel and asks the user once',
      '- ctx.permissions: request({name, host?}) / status({name, host?}) — explicitly request/query a runtime permission (notification.popup, clipboard.read, background.keepalive, net.host, login.open); returns {name, granted}',
      '- ctx.secrets: get/set/remove(key) — encrypted credentials (Keystore/Keychain), isolated by extension id; requires the secrets permission',
      '- ctx.net: request({method, url, headers, body, bodyBase64}) — native HTTPS proxy without CORS; can carry Cookie/Authorization headers; https only, private addresses blocked; the app asks the user once per host; requires the network permission',
      '- ctx.clipboard: read() / write(text) — reading requires the clipboard permission and a user consent prompt',
      '- ctx.files: pick({accept?, multiple?, encoding?}) → {files: [{name, size, mime, text?/base64?}]}; save({name, text?/base64?, mime?}) → true/false. Only through the system file picker; each file ≤ 8 MB. Requires the files permission. Use encoding: "base64" for binary files. An <a download> with blob:/data: is routed through files.save automatically.',
      '- ctx.login: open({url, cookieUrls, title?, successUrlPrefix?, successCookie?, userAgent?}) — visible login WebView; returns {cookies, cookieHeader} for the declared same-site domains; requires the login permission and a user consent prompt',
      '- ctx.background: keepAlive({enabled, title?, text?}) — starts/stops an Android foreground service with a persistent notification so the open extension page keeps running its timers in the background; requires the background permission and a user consent prompt',
      '- ctx.app: id/name/version/permissions/close()',
      'Cordis ctx.effect / ctx.on / ctx.plugin are also available.',
    ].join('\n'),
  },
  {
    name: 'constraints',
    order: 400,
    text: [
      '## Hard constraints',
      '- The page is an inline opaque origin: localStorage, sessionStorage and document.cookie throw. Use ctx.storage.',
      '- Do not load remote scripts or CSS. Prefer data: for images and fonts. Cross-origin or cookie-bearing requests must use ctx.net.request (network permission); plain fetch only works for CORS-enabled https and cannot set Cookie.',
      '- Notifications require the notification permission in ext.json; the first ctx.notify.* call asks the user for system notification permission.',
      '- Cookies / tokens go in ctx.secrets (secrets permission, Keystore/Keychain), never in ctx.storage or the DOM.',
      '- Use AntiUI for buttons, cards, fields, sheets and empty states. App colors come from CSS variables (--antisit-*), so do not hard-code light/dark colors; put only app-specific tweaks in style.css.',
      '- File input / download compatibility: use ctx.files.pick and ctx.files.save (files permission). Do not try to read arbitrary local paths or request storage permissions.',
      '- The app asks the user to confirm each new host used by ctx.net, clipboard reads, login pages, background keep-alive, and popup notifications. Do not try to avoid or pre-approve these prompts.',
      '- main.js is one file; do not use local imports. Put styles in style.css.',
      '- Draw inside ctx.ui.root. Do not read or write files outside the draft; do not try to run shell commands.',
    ].join('\n'),
  },
  {
    name: 'text-protocol',
    order: 900,
    text: (textMode) => textMode ? [
      '## Output protocol (this model does not support native tool calls)',
      'Output exactly one JSON object, no markdown fence, no extra text:',
      '- call a tool: {"tool":"write_file","args":{"path":"main.js","content":"..."}}',
      '- finish: {"final":"answer for the user"}',
      'Call one tool at a time and wait for its result before deciding the next step.',
    ].join('\n') : '',
  },
];

function assembleSystemPrompt(textMode) {
  return PROMPT_SECTIONS
    .slice()
    .sort((a, b) => a.order - b.order)
    .map((section) => typeof section.text === 'function' ? section.text(textMode) : section.text)
    .filter(Boolean)
    .join('\n\n');
}

/** DSH 风格的 runtime context：工作区状态作为 user-role 快照，而不是塞进 system。 */
function renderRuntimeContext(manifest, files) {
  const tree = files.length
    ? files.map((f) => '- ' + f.path + ' (' + f.size + ' B)').join('\n')
    : '（空）';
  const permissions = manifest.permissions && manifest.permissions.length
    ? manifest.permissions.join(', ')
    : '（无）';
  return [
    'Current runtime context. This snapshot supersedes earlier runtime-context snapshots.',
    '',
    'draft id: ' + manifest.id,
    'draft name: ' + manifest.name,
    'version: ' + manifest.version,
    'permissions: ' + permissions,
    'files:',
    tree,
  ].join('\n');
}

// ==================== 工具注册表 ====================

function argString(args, key, allowEmpty) {
  const value = args[key] == null ? '' : String(args[key]);
  if (!allowEmpty && value.trim().length === 0) throw new Error('缺少参数：' + key);
  return value;
}

function argInt(args, key, fallback, min, max) {
  if (args[key] == null) return fallback;
  const n = Number(args[key]);
  if (!Number.isFinite(n)) throw new Error(key + ' 必须是数字');
  return Math.max(min, Math.min(max, Math.trunc(n)));
}

function normalizeRead(value) {
  if (value && typeof value === 'object' && typeof value.content === 'string') {
    return { content: value.content, version: String(value.version || '') };
  }
  return { content: String(value || ''), version: '' };
}

function renderRead(path, content, offset, limit) {
  const lines = content.split('\n');
  const total = lines.length;
  const start = Math.max(1, Math.min(total, offset));
  const end = Math.min(total, start + limit - 1);
  let body = lines.slice(start - 1, end).join('\n');
  let truncated = end < total;
  if (body.length > MAX_READ_CHARS) {
    body = body.slice(0, MAX_READ_CHARS);
    truncated = true;
  }
  return [
    '<path>' + path + '</path>',
    '<lines>' + start + '-' + end + ' of ' + total + '</lines>',
    '<content>',
    body,
    '</content>',
    truncated ? '（内容未读完，用 offset 继续读）' : '',
  ].filter((line, i) => line !== '' || i === 4).join('\n');
}

const TOOL_DEFS = [
  {
    name: 'set_goal',
    readOnly: true,
    description: 'Set (or clear) the one objective this conversation is working toward.',
    prompt: 'declare the single concrete objective before multi-step work; clear it with an empty objective when the work is done or the user changes direction.',
    parameters: {
      type: 'object',
      properties: {
        objective: {
          type: 'string',
          description: 'One sentence describing the completion objective; empty string clears it.',
        },
      },
      required: ['objective'],
    },
    async run(args) {
      const objective = args.objective == null ? '' : String(args.objective).trim();
      if (objective.length > 400) throw new Error('目标太长（最多 400 字）');
      S.session.append('goal/set', { objective: objective });
      return objective ? '目标已记录：' + objective : '目标已清空。';
    },
  },
  {
    name: 'update_plan',
    readOnly: true,
    description: 'Publish or update the ordered step list for the current objective.',
    prompt: 'keep exactly one step in_progress while working; mark completed as soon as it is done. Pass the full list every time (not a delta).',
    parameters: {
      type: 'object',
      properties: {
        steps: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              content: { type: 'string', description: 'What the step does' },
              status: {
                type: 'string',
                enum: ['pending', 'in_progress', 'completed'],
              },
            },
            required: ['content'],
          },
        },
      },
      required: ['steps'],
    },
    async run(args) {
      const raw = Array.isArray(args.steps) ? args.steps : [];
      if (raw.length > 12) throw new Error('步骤最多 12 条');
      const steps = raw.map((s) => ({
        content: String((s && s.content) || '').slice(0, 160),
        status: ['pending', 'in_progress', 'completed'].includes(s && s.status)
          ? s.status
          : 'pending',
      }));
      S.session.append('plan/update', { steps: steps });
      if (!steps.length) return '计划已清空。';
      const done = steps.filter((s) => s.status === 'completed').length;
      return '计划已更新：' + done + ' / ' + steps.length + ' 步完成';
    },
  },  {
    name: 'mcp_list_tools',
    readOnly: true,
    description: 'List tools exposed by the MCP servers the user connected.',
    prompt: 'call it before using any mcp_call; it returns serverId + tool names.',
    parameters: { type: 'object', properties: {} },
    async run() {
      const result = await ctx.workshop.mcpTools();
      const servers = (result && result.servers) || [];
      if (!servers.length) return '（用户还没配置 MCP 服务器）';
      return servers
        .map((s) => {
          if (s.error) return s.serverId + '  ' + (s.server || '') + '  连接失败：' + s.error;
          return s.serverId + '  ' + (s.server || '') + '\n'
            + (s.tools || []).map((t) => '  - ' + t.name + ': ' + (t.description || '')).join('\n');
        })
        .join('\n');
    },
  },
  {
    name: 'mcp_call',
    readOnly: false,
    description: 'Call a tool on one of the MCP servers the user connected.',
    prompt: 'arguments must match the tool inputSchema from mcp_list_tools; the call is confirmed by the app unless full access is on.',
    parameters: {
      type: 'object',
      properties: {
        serverId: { type: 'string', description: 'Server id from mcp_list_tools' },
        tool: { type: 'string', description: 'Tool name' },
        arguments: { type: 'object', description: 'Arguments for the tool' },
      },
      required: ['serverId', 'tool'],
    },
    async run(args) {
      const serverId = argString(args, 'serverId');
      const tool = argString(args, 'tool');
      const toolArgs = (args && args.arguments) || {};
      // 确认框由宿主弹（和写文件一样走原生，网页没法伪造「已同意」）
      S.status = '等待确认调用 MCP 工具 ' + tool + '…';
      notify();
      try {
        const result = await ctx.workshop.mcpCall(serverId, tool, toolArgs);
        if (result && result.denied) throw new Error(result.reason || '用户拒绝调用 MCP 工具');
        return (result && result.content) || '（没有返回内容）';
      } finally {
        S.status = '';
        notify();
      }
    },
  },  {
    name: 'list_files',
    readOnly: true,
    description: 'List every file in the current draft and its size.',
    prompt: 'list the current draft tree; call it before reading or editing.',
    parameters: { type: 'object', properties: {} },
    async run() {
      await refreshFiles();
      return S.files.length
        ? S.files.map((f) => f.path + '  ' + f.size + ' B').join('\n')
        : '（空拓展）';
    },
  },
  {
    name: 'read_file',
    readOnly: true,
    description: 'Read a UTF-8 text file from the draft, optionally a line range.',
    prompt: 'read a draft file; returns a version used by write_file/edit_file. Use offset for large files.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Draft-relative path, e.g. main.js' },
        offset: { type: 'number', description: '1-based first line; defaults to 1' },
        limit: { type: 'number', description: 'Maximum lines; defaults to ' + DEFAULT_READ_LINES },
      },
      required: ['path'],
    },
    async run(args) {
      const path = argString(args, 'path');
      const read = normalizeRead(await ctx.workshop.read(S.draft.id, path));
      S.session.observe(path, read.version);
      return renderRead(
        path,
        read.content,
        argInt(args, 'offset', 1, 1, Number.MAX_SAFE_INTEGER),
        argInt(args, 'limit', DEFAULT_READ_LINES, 1, MAX_READ_LINES),
      );
    },
  },
  {
    name: 'write_file',
    readOnly: false,
    description: 'Create a file or fully replace a UTF-8 text file. Existing files must be read first.',
    prompt: 'create or replace a whole file; requires a prior read_file for existing files and always asks the user.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string' },
        content: { type: 'string', description: 'Full file content' },
      },
      required: ['path', 'content'],
    },
    async run(args) {
      const path = argString(args, 'path');
      const content = args.content == null ? '' : String(args.content);
      const known = S.session.observed.get(path);
      S.status = '等待确认写入 ' + path + '…';
      notify();
      const result = await ctx.workshop.write(S.draft.id, path, content, known);
      if (result && result.denied) throw new Error(result.reason || '用户拒绝写入');
      if (!result || result.ok !== true) throw new Error('写入失败');
      S.session.observe(path, result.version);
      try { await refreshFiles(); } catch (_) {}
      return (known == null ? 'Created ' : 'Updated ') + path + '（' + content.length + ' 字符）';
    },
  },
  {
    name: 'edit_file',
    readOnly: false,
    description: 'Edit an existing UTF-8 text file by replacing literal text.',
    prompt: 'replace a literal string in an existing file; oldText must occur exactly once unless replaceAll is true. Prefer this over write_file for small changes.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string' },
        oldText: { type: 'string', description: 'Literal text to replace; must be unique by default' },
        newText: { type: 'string', description: 'Replacement text; empty string deletes the match' },
        replaceAll: { type: 'boolean', description: 'Replace every occurrence; defaults to false' },
      },
      required: ['path', 'oldText', 'newText'],
    },
    async run(args) {
      const path = argString(args, 'path');
      const oldText = argString(args, 'oldText');
      const newText = args.newText == null ? '' : String(args.newText);
      if (oldText === newText) throw new Error('oldText 与 newText 相同，没有可改的内容');
      const read = normalizeRead(await ctx.workshop.read(S.draft.id, path));
      S.session.observe(path, read.version);
      const replaceAll = args.replaceAll === true;
      const count = read.content.split(oldText).length - 1;
      if (count === 0) throw new Error('文件里找不到 oldText，请重新 read_file 后再试');
      if (!replaceAll && count !== 1) {
        throw new Error('oldText 出现了 ' + count + ' 次；请提供更具体的 oldText，或设置 replaceAll=true');
      }
      const next = replaceAll
        ? read.content.split(oldText).join(newText)
        : read.content.replace(oldText, () => newText);
      S.status = '等待确认修改 ' + path + '…';
      notify();
      const result = await ctx.workshop.write(S.draft.id, path, next, read.version);
      if (result && result.denied) throw new Error(result.reason || '用户拒绝修改');
      if (!result || result.ok !== true) throw new Error('修改失败');
      S.session.observe(path, result.version);
      try { await refreshFiles(); } catch (_) {}
      return 'Updated ' + path + '（替换 ' + (replaceAll ? count : 1) + ' 处）';
    },
  },
  {
    name: 'delete_file',
    readOnly: false,
    description: 'Delete a file from the draft. The file must be read first.',
    prompt: 'delete a draft file; requires a prior read_file and asks the user.',
    parameters: {
      type: 'object',
      properties: { path: { type: 'string' } },
      required: ['path'],
    },
    async run(args) {
      const path = argString(args, 'path');
      const version = S.session.observed.get(path);
      if (version == null) throw new Error('删除前先 read_file：' + path);
      S.status = '等待确认删除 ' + path + '…';
      notify();
      const result = await ctx.workshop.remove(S.draft.id, path, version);
      if (result && result.denied) throw new Error(result.reason || '用户拒绝删除');
      S.session.forget(path);
      try { await refreshFiles(); } catch (_) {}
      return 'Deleted ' + path;
    },
  },
  {
    name: 'validate_extension',
    readOnly: true,
    description: 'Check ext.json, main.js and common inline-page mistakes. Call it after edits.',
    prompt: 'lint the draft: manifest, entry, localStorage/cookie, network declarations, external scripts.',
    parameters: { type: 'object', properties: {} },
    async run() {
      const result = await ctx.workshop.validate(S.draft.id);
      return result && result.ok
        ? '校验通过：ext.json 与 main.js 没问题'
        : ((result && result.problems) || ['校验失败']).join('\n');
    },
  },
  {
    name: 'preview_extension',
    readOnly: false,
    description: 'Open the current draft in the app using the Cordis runtime.',
    prompt: 'open a live preview of the draft; use it after validating UI changes.',
    parameters: { type: 'object', properties: {} },
    async run() {
      await ctx.workshop.preview(S.draft.id);
      return '已在 App 内打开预览';
    },
  },
  {
    name: 'install_extension',
    readOnly: false,
    description: 'Install the draft as a real extension. Only call when the user explicitly asks.',
    prompt: 'copy the draft into the extension list; only when the user explicitly asks; asks the user.',
    parameters: { type: 'object', properties: {} },
    async run() {
      S.status = '等待确认安装 ' + S.draft.name + '…';
      notify();
      const result = await ctx.workshop.install(S.draft.id);
      if (result && result.denied) throw new Error(result.reason || '用户拒绝安装');
      try { await refreshDraftList(); } catch (_) {}
      return '已安装「' + ((result && result.name) || S.draft.name) + '」（' + ((result && result.id) || S.draft.id) + '）';
    },
  },
  {
    name: 'list_skills',
    readOnly: true,
    description: 'List installed reusable skills (name + description).',
    prompt: 'list the skill library; call it before starting a task that may match a skill.',
    parameters: { type: 'object', properties: {} },
    async run() {
      await refreshSkills();
      return S.skills.length
        ? S.skills.map((s) => s.id + '  ' + s.name + ' — ' + (s.description || '（无说明）')).join('\n')
        : '（还没有安装技能）';
    },
  },
  {
    name: 'read_skill',
    readOnly: true,
    description: 'Read the full instruction document of an installed skill.',
    prompt: 'read one skill by id or name; apply its instructions to the current task.',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Skill id from list_skills' },
        name: { type: 'string', description: 'Skill name (alternative to id)' },
      },
    },
    async run(args) {
      const id = args && args.id ? String(args.id) : '';
      const name = args && args.name ? String(args.name) : '';
      const skill = S.skills.find((s) => (id && s.id === id) || (name && s.name === name));
      if (!skill) throw new Error('没有这条技能，先用 list_skills 看');
      const result = await ctx.workshop.readSkill(skill.id);
      return '<skill id="' + skill.id + '">\n'
        + String((result && result.content) || '') + '\n</skill>';
    },
  },
  {
    name: 'install_skill',
    readOnly: false,
    description: 'Install or update a reusable skill (instruction document) for future tasks.',
    prompt: 'save a reusable skill with name / description / markdown content; asks the user unless full access is on.',
    parameters: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Skill name, at most 40 chars' },
        description: { type: 'string', description: 'One-line trigger description' },
        content: { type: 'string', description: 'Full markdown instructions' },
      },
      required: ['name', 'content'],
    },
    async run(args) {
      const name = argString(args, 'name');
      const content = args.content == null ? '' : String(args.content);
      const description = args.description == null ? '' : String(args.description);
      S.status = '等待确认安装技能 ' + name + '…';
      notify();
      const result = await ctx.workshop.installSkill(name, description, content);
      if (result && result.denied) throw new Error(result.reason || '用户拒绝安装技能');
      if (!result || result.ok !== true) throw new Error('技能安装失败');
      await refreshSkills();
      return '已安装技能「' + (result.name || name) + '」（' + (result.id || '') + '），以后用 read_skill 读取。';
    },
  },
  {
    name: 'delete_skill',
    readOnly: false,
    description: 'Delete an installed skill by id.',
    prompt: 'remove a skill the user no longer wants; asks the user.',
    parameters: {
      type: 'object',
      properties: { id: { type: 'string' } },
      required: ['id'],
    },
    async run(args) {
      const id = argString(args, 'id');
      S.status = '等待确认删除技能…';
      notify();
      const result = await ctx.workshop.deleteSkill(id);
      if (result && result.denied) throw new Error(result.reason || '用户拒绝删除技能');
      await refreshSkills();
      return '已删除技能 ' + id;
    },
  },
];

function toolByName(name) {
  return TOOL_DEFS.find((tool) => tool.name === name);
}

/** 计划模式只暴露只读工具；完全访问不影响可用工具，只影响确认框。 */
function availableTools() {
  return S && S.planMode ? TOOL_DEFS.filter((tool) => tool.readOnly) : TOOL_DEFS;
}

function toolSpecs() {
  return availableTools().map((tool) => ({
    name: tool.name,
    description: tool.description,
    parameters: tool.parameters,
  }));
}

// ==================== 工具执行 ====================

function abortedError() {
  return new Error('tool call aborted before dispatch');
}

async function executeOne(call, signal) {
  const tool = toolByName(call.name);
  if (!tool) {
    return {
      content: 'Error: unknown tool "' + call.name + '". Available: ' + availableTools().map((t) => t.name).join(', '),
      isError: true,
    };
  }
  // 计划模式是只读的：即使模型从文本协议里硬塞一个写工具也不执行
  if (S.planMode && !tool.readOnly) {
    return {
      content: 'Error: plan mode only allows read-only tools. Turn plan mode off to modify files or install.',
      isError: true,
    };
  }
  let args;
  try {
    args = typeof call.arguments === 'string' ? JSON.parse(call.arguments || '{}') : (call.arguments || {});
    if (!args || typeof args !== 'object' || Array.isArray(args)) throw new Error('参数必须是 JSON 对象');
  } catch (e) {
    return { content: 'Error: 参数不是合法 JSON：' + (e && e.message ? e.message : e), isError: true };
  }
  if (signal && signal.aborted) {
    return { content: 'Error: tool call aborted before dispatch', isError: true, code: 'ABORTED_BEFORE_DISPATCH' };
  }
  try {
    const value = await tool.run(args, { signal: signal });
    const content = typeof value === 'string' ? value : String((value && value.content) || '');
    return {
      content: content.slice(0, MAX_TOOL_RESULT_CHARS),
      isError: !!(value && value.isError),
    };
  } catch (e) {
    return {
      content: 'Error: ' + (e && e.message ? e.message : String(e)),
      isError: true,
    };
  }
}

/**
 * 按 DSH 的批量规则执行：连续只读工具可并发，写/安装形成独占屏障。
 * 所有调用先落 tool/call，结果按模型给出的顺序落 tool/result。
 */
async function executeBatch(calls, signal) {
  const results = new Array(calls.length);
  let i = 0;
  while (i < calls.length) {
    if (signal && signal.aborted) {
      for (let j = i; j < calls.length; j++) {
        results[j] = { content: 'Error: tool call aborted before dispatch', isError: true, code: 'ABORTED_BEFORE_DISPATCH' };
      }
      break;
    }
    const tool = toolByName(calls[i].name);
    if (tool && tool.readOnly) {
      const indices = [];
      while (i < calls.length && !(signal && signal.aborted)) {
        const next = toolByName(calls[i].name);
        if (!next || !next.readOnly) break;
        indices.push(i);
        i += 1;
      }
      const group = await Promise.all(indices.map((index) => executeOne(calls[index], signal)));
      group.forEach((result, k) => { results[indices[k]] = result; });
    } else {
      results[i] = await executeOne(calls[i], signal);
      i += 1;
    }
  }
  for (let k = 0; k < calls.length; k++) {
    if (!results[k]) {
      results[k] = { content: 'Error: tool call aborted before dispatch', isError: true, code: 'ABORTED_BEFORE_DISPATCH' };
    }
  }
  return results;
}

function normalizeToolCalls(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  raw.forEach((call, index) => {
    if (!call || !call.name) return;
    let args = call.arguments;
    if (args && typeof args !== 'string') args = JSON.stringify(args);
    out.push({
      id: String(call.id || 'call_' + Date.now().toString(36) + '_' + index),
      name: String(call.name),
      arguments: String(args || '{}'),
    });
  });
  return out;
}

// ==================== 模型调用 ====================

function isNonRetryable(error) {
  const text = String((error && error.message) || error || '');
  return /尚未配置|还没配好|API Key|401|403|未授权|余额|额度|不存在/.test(text);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function callModel(turn, step, signal) {
  const messages = S.session.deriveMessages();
  const tools = S.textMode ? [] : toolSpecs();
  let lastError;
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    if (signal && signal.aborted) throw new Error('aborted');
    S.stream = {
      id: 'st' + Date.now().toString(36) + '_' + attempt,
      text: '',
      reasoning: '',
    };
    try {
      S.status = attempt === 1 ? '思考中…' : '模型请求失败，重试中…';
      notify();
      const stream = ctx.ai.chatToolsStream;
      if (typeof stream !== 'function') {
        // 老宿主没有流式接口：退回一次性请求，S.stream 保持为空
        return await ctx.ai.chatTools({
          messages: messages,
          tools: tools,
          maxTokens: 4096,
          reasoningEffort: S.effort || '',
        });
      }
      return await stream.call(ctx.ai, {
        streamId: S.stream.id,
        messages: messages,
        tools: tools,
        maxTokens: 4096,
        reasoningEffort: S.effort || '',
      });
    } catch (e) {
      lastError = e;
      S.stream = null;
      if (signal && signal.aborted) throw e;
      S.session.append('assistant/attempt', {
        turn: turn,
        step: step,
        error: String((e && e.message) || e),
      });
      if (attempt >= 2 || isNonRetryable(e)) throw e;
      await sleep(500);
    }
  }
  throw lastError;
}

// ==================== turn / step ====================

function abortReason() {
  return { kind: 'aborted', reason: { kind: 'user' } };
}

function appendAbortedReply(reply, turn, step, reasoning) {
  if (!reply) return;
  const text = String(reply.text || '').trim();
  if (text || reasoning) {
    S.session.append('assistant/message', {
      turn: turn,
      step: step,
      text: text,
      reasoning: reasoning || '',
      interrupted: true,
    });
  }
}

/** 步骤异常退出时，给这一 step 里没有结果的 tool call 补一条错误结果，保持协议配对。 */
function repairStepToolCalls(turn, step) {
  const assistants = S.session.events.filter((e) =>
    e.type === 'assistant/message' && e.turn === turn && e.step === step
    && Array.isArray(e.toolCalls) && e.toolCalls.length > 0);
  for (const message of assistants) {
    for (const call of message.toolCalls) {
      if (!call || !call.id) continue;
      if (S.session.events.some((e) => e.type === 'tool/result' && e.callId === call.id)) continue;
      S.session.append('tool/result', {
        turn: turn,
        step: step,
        callId: call.id,
        name: call.name,
        isError: true,
        recovered: true,
        content: 'Error: tool call outcome is unknown. Check the workspace before retrying.',
      });
    }
  }
}

async function runStep(turn, step) {
  let manifest;
  try {
    manifest = await readManifest();
  } catch (e) {
    manifest = S.draft || { id: '', name: '', version: '', permissions: [] };
  }
  await refreshFiles();
  await refreshSkills();
  const system = assembleSystemPrompt(S.textMode);
  const lastSystem = findLast('system/message');
  if (!lastSystem || lastSystem.text !== system) {
    S.session.append('system/message', { turn: turn, step: step, text: system });
  }
  const context = renderRuntimeContext(manifest, S.files);
  const lastContext = findLast('context/message');
  if (!lastContext || lastContext.content !== context) {
    S.session.append('context/message', { turn: turn, step: step, content: context, source: 'runtime-context' });
  }

  let reply;
  try {
    reply = await callModel(turn, step, S.abort);
  } catch (e) {
    S.stream = null;
    if (S.abort && S.abort.aborted) return abortReason();
    throw e;
  }
  const streamed = S.stream || { text: '', reasoning: '' };
  const reasoning = String((reply && reply.reasoning) || streamed.reasoning || '').trim();
  const replyText = String((reply && reply.text) || streamed.text || '');
  S.stream = null;
  if (S.abort && S.abort.aborted) {
    appendAbortedReply(reply, turn, step, reasoning);
    return abortReason();
  }

  const wasTextMode = S.textMode;
  if (reply && reply.usedTools === false) S.textMode = true;
  const calls = wasTextMode ? [] : normalizeToolCalls(reply && reply.toolCalls);

  if (calls.length > 0) {
    S.session.append('assistant/message', {
      turn: turn,
      step: step,
      text: replyText,
      reasoning: reasoning,
      toolCalls: calls,
    });
    for (const call of calls) {
      S.session.append('tool/call', {
        turn: turn,
        step: step,
        callId: call.id,
        name: call.name,
        arguments: call.arguments,
      });
    }
    S.status = '执行 ' + calls.map((c) => c.name).join(' / ') + '…';
    notify();
    const results = await executeBatch(calls, S.abort);
    for (let i = 0; i < calls.length; i += 1) {
      const call = calls[i];
      const result = results[i] || { content: 'Error: tool did not run', isError: true };
      S.session.append('tool/result', {
        turn: turn,
        step: step,
        callId: call.id,
        name: call.name,
        content: String(result.content || '').slice(0, MAX_TOOL_RESULT_CHARS),
        isError: !!result.isError,
        ...(result.code ? { code: result.code } : {}),
      });
    }
    if (S.abort && S.abort.aborted) return abortReason();
    if (reply && reply.finishReason === 'length') return { kind: 'max-tokens' };
    return null;
  }

  if (wasTextMode) {
    const action = parseAction(String((reply && reply.text) || ''));
    if (action && typeof action.tool === 'string') {
      const call = {
        id: 'text_' + Date.now().toString(36),
        name: action.tool,
        arguments: JSON.stringify(action.args || {}),
      };
      S.session.append('assistant/message', {
        turn: turn,
        step: step,
        text: String((reply && reply.text) || ''),
        reasoning: reasoning,
        hidden: true,
      });
      S.session.append('tool/call', {
        turn: turn,
        step: step,
        callId: call.id,
        name: call.name,
        arguments: call.arguments,
        textProtocol: true,
      });
      S.status = '执行 ' + call.name + '…';
      notify();
      const result = await executeOne(call, S.abort);
      S.session.append('tool/result', {
        turn: turn,
        step: step,
        callId: call.id,
        name: call.name,
        content: String(result.content || '').slice(0, MAX_TOOL_RESULT_CHARS),
        isError: !!result.isError,
        textProtocol: true,
        ...(result.code ? { code: result.code } : {}),
      });
      S.session.append('user/message', {
        source: 'tool-result',
        content: '工具结果（' + call.name + '）：' + String(result.content || ''),
      });
      if (S.abort && S.abort.aborted) return abortReason();
      return null;
    }
    const finalText = action && typeof action.final === 'string'
      ? action.final
      : String((reply && reply.text) || '').trim();
    if (!finalText) throw new Error('AI 没有给出内容，请重试');
    S.session.append('assistant/message', { turn: turn, step: step, text: finalText });
    if (S.inbox.nextStep.length > 0) return null;
    return reply && reply.finishReason === 'length' ? { kind: 'max-tokens' } : { kind: 'completed' };
  }

  const text = String(replyText || '').trim();
  if (!text) throw new Error('AI 没有给出内容，请重试');
  S.session.append('assistant/message', {
    turn: turn,
    step: step,
    text: text,
    reasoning: reasoning,
  });
  if (S.inbox.nextStep.length > 0) return null;
  return reply && reply.finishReason === 'length' ? { kind: 'max-tokens' } : { kind: 'completed' };
}

async function runTurn(turn) {
  S.session.append('turn/start', { turn: turn });
  let step = 0;
  let ending = null;
  let first = true;
  let continueWithoutInput = false;
  while (!ending) {
    if (S.abort && S.abort.aborted) {
      ending = abortReason();
      break;
    }
    const claimed = first ? S.inbox.claimTurn() : S.inbox.claimStep();
    first = false;
    // 工具结果本身也是下一步的输入；没有新插话时仍要继续请求模型。
    if (claimed.length === 0 && !continueWithoutInput) break;
    continueWithoutInput = false;
    step += 1;
    if (step > MAX_STEPS) {
      for (const message of claimed) {
        S.pending = S.pending.filter((item) => item !== message);
        S.session.append('user/message', { content: message.text, source: 'user' });
      }
      S.session.append('error', { text: '这一轮已经连续执行 ' + MAX_STEPS + ' 步，先停一下；继续发消息可以接着改。' });
      ending = { kind: 'completed' };
      break;
    }
    S.session.append('step/start', { turn: turn, step: step });
    for (const message of claimed) {
      S.pending = S.pending.filter((item) => item !== message);
      S.session.append('user/message', { content: message.text, source: 'user' });
    }
    try {
      ending = await runStep(turn, step);
    } catch (e) {
      repairStepToolCalls(turn, step);
      S.session.append('error', { text: String((e && e.message) || e) });
      ending = { kind: 'error', error: String((e && e.message) || e) };
    } finally {
      S.session.append('step/end', { turn: turn, step: step });
    }
    if (ending) break;
    // null 表示「这一步还要继续」：刚跑完工具，或运行中被插话。
    continueWithoutInput = true;
  }
  S.session.append('turn/end', { turn: turn, reason: ending || { kind: 'completed' } });
  return ending;
}

async function runAgent() {
  if (S.running || !S.session) return;
  S.running = true;
  S.abort = { aborted: false, abort() { this.aborted = true; } };
  notify();
  try {
    while (S.inbox.hasPending() && !S.abort.aborted) {
      const turn = S.session.nextTurn();
      await runTurn(turn);
      if (S.abort.aborted) break;
      if (!S.inbox.hasPending()) break;
    }
  } catch (e) {
    S.session.append('error', { text: '运行失败：' + String((e && e.message) || e) });
  } finally {
    S.running = false;
    S.abort = null;
    S.status = '';
    notify();
    if (S.session) await S.session.flush();
    try {
      await refreshConversations();
    } catch (_) {}
  }
}

function findLast(type) {
  for (let i = S.session.events.length - 1; i >= 0; i -= 1) {
    if (S.session.events[i].type === type) return S.session.events[i];
  }
  return null;
}

// ==================== 拓展 / 文件 ====================

async function refreshDraftList() {
  const result = await ctx.workshop.list();
  S.drafts = (result && result.drafts) || [];
  if (S.draft) {
    const current = S.drafts.find((d) => d.id === S.draft.id);
    if (current) S.draft = current;
  }
  notify();
}

async function refreshFiles() {
  if (!S.draft) {
    S.files = [];
    return;
  }
  const result = await ctx.workshop.files(S.draft.id);
  S.files = (result && result.files) || [];
}

async function refreshSkills() {
  try {
    const result = await ctx.workshop.listSkills();
    S.skills = (result && result.skills) || [];
  } catch (e) {
    S.skills = [];
    console.warn('[workshop] 技能库读取失败', e);
  }
  // 「/」面板里的技能候选跟着刷新（技能可能刚被导入 / 删除）。
  // syncSlash 定义在 apply() 作用域里，模块作用域拿不到，通过 S 上的钩子回调。
  if (S && S.slashOpen && S.syncSlash) S.syncSlash();
}

async function readManifest() {
  const base = S.draft;
  try {
    const raw = normalizeRead(await ctx.workshop.read(S.draft.id, 'ext.json')).content;
    const manifest = JSON.parse(raw);
    return {
      id: manifest.id || base.id,
      name: manifest.name || base.name,
      version: manifest.version || base.version,
      permissions: Array.isArray(manifest.permissions) ? manifest.permissions : [],
    };
  } catch (_) {
    return base;
  }
}

async function refreshConversations() {
  if (!S.draft) {
    S.conversations = [];
    return;
  }
  const result = await ctx.workshop.listConversations(S.draft.id);
  S.conversations = (result && result.conversations) || [];
}

async function selectConversation(id) {
  if (!S.draft || S.running || !id) return;
  if (S.session && S.session.conversationId !== id) await S.session.flush();
  S.conversationId = id;
  S.inbox.clear();
  S.pending = [];
  S.textMode = false;
  S.stream = null;
  S.session = await AgentSession.load(ctx.workshop, S.draft.id, id, onSessionChange);
  try {
    await ctx.storage.set('conv:' + S.draft.id, id);
  } catch (_) {}
  notify();
}

async function newConversation() {
  if (!S.draft || S.running) return null;
  if (S.session) await S.session.flush();
  const created = await ctx.workshop.createConversation(S.draft.id, '新对话');
  S.conversations = [created].concat(S.conversations.filter((c) => c.id !== created.id));
  await selectConversation(created.id);
  return created;
}

async function deleteCurrentConversation() {
  if (!S.draft || S.running || !S.conversationId) return;
  // 先把待落盘的会话写完，再删文件；否则延迟保存会把刚删的对话又写回来
  if (S.session) await S.session.flush();
  const result = await ctx.workshop.deleteConversation(S.draft.id, S.conversationId);
  if (result && result.denied) return;
  S.session = null;
  S.conversationId = null;
  await refreshConversations();
  if (!S.conversations.length) {
    await newConversation();
  } else {
    await selectConversation(S.conversations[0].id);
  }
  notify();
}

async function deleteCurrentDraft() {
  if (!S.draft || S.running) return;
  if (S.draft.installed) {
    ctx.ui.toast('这个拓展已经安装：先到「拓展」页卸载，再删拓展');
    return;
  }
  // 先 flush 再删目录：反过来写会话文件会把刚删掉的目录又建回来
  if (S.session) await S.session.flush();
  const result = await ctx.workshop.deleteDraft(S.draft.id);
  if (result && result.denied) return;
  S.session = null;
  S.conversationId = null;
  S.draft = null;
  await refreshDrafts();
  ctx.ui.toast('拓展已删除');
}

async function selectDraft(draft) {
  if (S.session) await S.session.flush();
  S.draft = draft;
  S.inbox.clear();
  S.pending = [];
  S.textMode = false;
  S.stream = null;
  S.files = [];
  S.session = null;
  S.conversationId = null;
  await refreshFiles();
  await refreshConversations();
  let cid = null;
  try {
    cid = await ctx.storage.get('conv:' + draft.id);
  } catch (_) {}
  if (!cid || !S.conversations.some((c) => c.id === cid)) {
    cid = S.conversations.length ? S.conversations[0].id : null;
  }
  if (!cid) {
    const created = await ctx.workshop.createConversation(draft.id, '新对话');
    S.conversations = [created];
    cid = created.id;
  }
  await selectConversation(cid);
}

async function refreshDrafts(prefer) {
  await refreshDraftList();
  if (!S.drafts.length) {
    const draft = await ctx.workshop.create('我的第一个拓展');
    S.drafts = [draft];
  }
  const id = prefer || (S.draft && S.draft.id);
  const next = S.drafts.find((d) => d.id === id) || S.drafts[0];
  if (!S.draft || S.draft.id !== next.id || !S.session) {
    await selectDraft(next);
  } else {
    S.draft = next;
    await refreshFiles();
    await refreshConversations();
    if (!S.conversationId
        || !S.conversations.some((c) => c.id === S.conversationId)) {
      if (S.conversations.length) {
        await selectConversation(S.conversations[0].id);
      } else {
        await newConversation();
      }
    }
    notify();
  }
}

// ==================== 文本协议 ====================

function parseAction(text) {
  let s = String(text || '').trim();
  if (s.startsWith('```')) {
    s = s.replace(/^```[a-zA-Z]*\s*/, '');
    const end = s.lastIndexOf('```');
    if (end >= 0) s = s.slice(0, end);
    s = s.trim();
  }
  const start = s.indexOf('{');
  const end = s.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    const raw = JSON.parse(s.slice(start, end + 1));
    return raw && typeof raw === 'object' ? raw : null;
  } catch (_) {
    return null;
  }
}

// ==================== 页面 ====================

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** 行内 markdown：`code` 与 **粗体**（先转义，再替换，不会带进标签）。 */
function mdInline(text) {
  return text
    .replace(/`([^`\n]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*\n]+)\*\*/g, '<b>$1</b>');
}

/** 一段纯文本 → 标题 / 列表 / 引用 / 段落（DSH 那种轻 markdown 渲染）。
    先逐行转义再套行内格式，模型输出里的 HTML 不会被当标签执行。 */
function mdText(raw) {
  let out = '';
  for (const rawLine of String(raw || '').split('\n')) {
    const line = esc(rawLine);
    const t = line.trim();
    if (!t) {
      out += '<div class="md-gap"></div>';
      continue;
    }
    let m = t.match(/^(#{1,4})\s+(.*)$/);
    if (m) {
      out += '<div class="md-h md-h' + m[1].length + '">' + mdInline(m[2]) + '</div>';
      continue;
    }
    m = t.match(/^[-*]\s+(.*)$/);
    if (m) {
      out += '<div class="md-li">' + mdInline(m[1]) + '</div>';
      continue;
    }
    m = t.match(/^(\d+)[.)]\s+(.*)$/);
    if (m) {
      out += '<div class="md-li md-num-li"><span class="md-num">' + m[1] + '.</span>'
        + mdInline(m[2]) + '</div>';
      continue;
    }
    m = t.match(/^&gt;\s?(.*)$/);
    if (m) {
      out += '<div class="md-quote">' + mdInline(m[1]) + '</div>';
      continue;
    }
    out += '<div class="md-p">' + mdInline(line) + '</div>';
  }
  return out;
}

/** 代码块（带语言标签与「复制」）：DSH Go 那种灰底、圆角、头部一行。 */
function codeBlock(lang, code) {
  return '<div class="code">'
    + '<div class="code-head"><span>' + esc(lang || 'text') + '</span>'
    + '<button class="code-copy" data-copy>复制</button></div>'
    + '<pre><code>' + esc(String(code || '').replace(/\n$/, '')) + '</code></pre></div>';
}

/** markdown 正文 → HTML：围栏代码块单独渲染，其余按行处理。流式时未闭合的围栏也能显示。 */
function md(raw) {
  const text = String(raw || '');
  const out = [];
  const re = /```([^\n`]*)\n?([\s\S]*?)(?:```|$)/g;
  let last = 0;
  let m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) out.push(mdText(text.slice(last, m.index)));
    out.push(codeBlock(m[1].trim(), m[2]));
    last = re.lastIndex;
    if (!m[2]) break;
  }
  if (last < text.length) out.push(mdText(text.slice(last)));
  return out.join('');
}

/** 复制到剪贴板（WebView 里 navigator.clipboard 可能不可用，退回 textarea）。 */
function copyText(text) {
  const value = String(text || '');
  if (!value) return;
  const fallback = () => {
    const ta = document.createElement('textarea');
    ta.value = value;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    try {
      document.execCommand('copy');
      ctx.ui.toast('已复制');
    } catch (_) {
      ctx.ui.toast('复制失败');
    }
    ta.remove();
  };
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(value).then(() => ctx.ui.toast('已复制'), fallback);
  } else {
    fallback();
  }
}

export default {
  name: 'ext-workshop',
  inject: ['ui', 'ai', 'workshop'],
  async apply(hostCtx) {
    ctx = hostCtx;
    const root = ctx.ui.root;
    S = {
      drafts: [],
      draft: null,
      files: [],
      conversations: [],
      conversationId: null,
      session: null,
      inbox: new Inbox(),
      pending: [],
      running: false,
      abort: null,
      textMode: false,
      stream: null,
      planMode: false,
      fullAccess: false,
      // 模型 / 思考深度：都要持久化（用户换过一次，下次进工坊还是那个）
      model: '',
      models: [],
      effort: '', // '' = 提供商默认；none / low / medium / high
      // 语音：micReady = 宿主有可用识别服务；listening = 正在录
      micReady: false,
      listening: false,
      micBase: '', // 开始录音时输入框里已有的文字（识别结果接在它后面）
      skills: [],
      status: '',
      tab: 'chat',
      // 「/」命令面板：open = 弹出中，items = 当前候选，index = 高亮项
      slashOpen: false,
      slashItems: [],
      slashIndex: 0,
      slashQuery: '',
      alive: true,
    };

    root.innerHTML = `
      <div class="ws">
        <header class="ws-head">
          <div class="ws-bar">
            <button id="btnSwitch" class="ws-icon" aria-label="切换拓展或对话"></button>
            <div class="ws-heading">
              <span class="ws-title" id="convTitle">新对话</span>
              <span class="ws-sub" id="draftMeta"></span>
            </div>
            <button id="btnPublish" class="ws-publish" aria-label="发布这个拓展">发布</button>
            <button id="btnMore" class="ws-icon" aria-label="更多"></button>
          </div>
          <nav class="ws-tabs">
            <button class="ws-tab active" data-tab="chat">对话</button>
            <button class="ws-tab" data-tab="files">文件</button>
          </nav>
        </header>
        <main class="ws-chat" id="chat"></main>
        <section class="ws-files hidden" id="filesPanel">
          <div class="files-head">
            <span id="filesCount">文件</span>
            <button id="btnRefreshFiles" class="ws-link">刷新</button>
          </div>
          <div class="file-list" id="files"></div>
        </section>
        <footer class="ws-composer">
          <div class="composer-slash hidden" id="slashPanel"></div>
          <div class="composer">
            <textarea id="input" rows="1" placeholder="说说要做什么，或者打 / 挑工具、挑技能"></textarea>
            <div class="composer-bar">
              <button id="btnPlan" class="chip" aria-label="计划模式">计划</button>
              <button id="btnFull" class="chip danger" aria-label="完全访问">完全访问</button>
              <button id="btnModel" class="chip" aria-label="切换模型">模型</button>
              <button id="btnEffort" class="chip" aria-label="思考深度">思考</button>
              <span class="composer-grow"></span>
              <button id="btnMic" class="icon-btn hidden" aria-label="语音输入"></button>
              <button id="btnStop" class="icon-btn hidden" aria-label="停止"></button>
              <button id="btnSend" class="icon-btn send" aria-label="发送"></button>
            </div>
          </div>
          <div class="ws-meta"><span id="metaLine"></span><span id="status" class="hidden"></span></div>
        </footer>
        <div class="ws-menu hidden" id="moreMenu">
          <button data-act="skills">技能</button>
          <button data-act="mcp">外部工具服务器</button>
          <button data-act="preview">预览拓展</button>
          <button data-act="install">安装拓展</button>
          <button data-act="publish">发布这个拓展</button>
          <button data-act="newConv">新建对话</button>
          <button data-act="newDraft">新建拓展</button>
          <button data-act="renameConv">重命名当前对话</button>
          <button data-act="renameDraft">重命名当前拓展</button>
          <button data-act="deleteConv" class="danger">删除当前对话</button>
          <button data-act="deleteDraft" class="danger">删除当前拓展</button>
        </div>
        <div class="ws-prompt hidden" id="prompt">
          <div class="prompt-card">
            <div class="prompt-title" id="promptTitle"></div>
            <input id="promptInput" maxlength="48" autocomplete="off">
            <div class="prompt-actions">
              <button id="promptCancel" class="ws-link">取消</button>
              <button id="promptOk" class="prompt-ok">确定</button>
            </div>
          </div>
        </div>
        <div class="ws-prompt hidden" id="pastePanel">
          <div class="prompt-card">
            <div class="prompt-title" id="pasteTitle">粘贴内容</div>
            <textarea id="pasteInput" rows="8" placeholder="粘贴 SKILL.md 的内容…"></textarea>
            <div class="prompt-actions">
              <button id="pasteCancel" class="ws-link">取消</button>
              <button id="pasteOk" class="prompt-ok">导入</button>
            </div>
          </div>
        </div>
        <div class="ws-backdrop hidden" id="backdrop"></div>
        <div class="ws-sheet hidden" id="switchSheet">
          <div class="sheet-handle"></div>
          <div class="sheet-label">拓展</div>
          <div id="draftList"></div>
          <div class="sheet-label">对话</div>
          <div id="convList"></div>
        </div>
        <div class="ws-sheet hidden" id="modelSheet">
          <div class="sheet-handle"></div>
          <div class="sheet-head"><strong>模型</strong><button id="btnCloseModel" class="ws-link">关闭</button></div>
          <div class="sheet-label">思考深度</div>
          <div id="effortList"></div>
          <div class="sheet-label">可用模型</div>
          <div id="modelList"></div>
        </div>
        <div class="ws-sheet hidden" id="mcpDrawer">
          <div class="sheet-handle"></div>
          <div class="sheet-head"><strong>外部工具服务器</strong><button id="btnCloseMcp" class="ws-link">关闭</button></div>
          <div class="mcp-add">
            <input id="mcpUrl" placeholder="服务器地址，例如 https://example.com/mcp" autocomplete="off">
            <div class="mcp-add-row">
              <input id="mcpAuth" placeholder="认证头，可留空" autocomplete="off">
              <button id="btnAddMcp" class="chip">添加</button>
              <button id="btnPasteMcp" class="chip" aria-label="从剪贴板粘贴配置">粘贴</button>
            </div>
          </div>
          <div id="mcpList"></div>
          <div class="sheet-label">工具</div>
          <div id="mcpTools"></div>
        </div>
        <div class="ws-sheet hidden" id="skillsDrawer">
          <div class="sheet-handle"></div>
          <div class="sheet-head"><strong>技能</strong><button id="btnCloseSkills" class="ws-link">关闭</button></div>
          <div class="skill-tools">
            <button id="btnImportSkillFile" class="chip">导入技能文件</button>
            <button id="btnImportSkillText" class="chip">粘贴技能</button>
          </div>
          <div id="skills"></div>
        </div>
        <div class="ws-viewer hidden" id="viewer">
          <div class="viewer-head"><strong id="viewerTitle"></strong><button id="btnCloseViewer" class="ws-link">关闭</button></div>
          <pre id="viewerBody"></pre>
        </div>
      </div>`;

    const $ = (sel) => root.querySelector(sel);
    const chat = $('#chat');
    const input = $('#input');
    const status = $('#status');
    const filesPanel = $('#filesPanel');
    const switchSheet = $('#switchSheet');
    const modelSheet = $('#modelSheet');
    const mcpDrawer = $('#mcpDrawer');
    const skillsDrawer = $('#skillsDrawer');
    const backdrop = $('#backdrop');
    const viewer = $('#viewer');
    const moreMenu = $('#moreMenu');
    let renderScheduled = false;

    // 内联 SVG 图标：不依赖 emoji 也不依赖图标字体（emoji 在不同 ROM 上大小不一、
    // 还可能被当成表情，这在 DSH 那套界面里是不出现的）。
    $('#btnSwitch').innerHTML = ICONS.menu;
    $('#btnMore').innerHTML = ICONS.more;
    $('#btnMic').innerHTML = ICONS.mic;
    $('#btnStop').innerHTML = ICONS.stop;
    $('#btnSend').innerHTML = ICONS.send;

    // AI 流式增量：只认当前这一轮的 streamId（重试会换 id）
    if (window.antiSIT && typeof window.antiSIT.on === 'function') {
      window.antiSIT.on('ai.stream', (data) => {
        if (!S.alive || !S.stream || !data) return;
        if (data.streamId !== S.stream.id) return;
        const delta = typeof data.delta === 'string' ? data.delta : '';
        if (!delta) return;
        if (data.kind === 'reasoning') {
          S.stream.reasoning += delta;
        } else {
          S.stream.text += delta;
        }
        scheduleRender();
      });
    }


    // ---------- 语音输入 ----------

    function applyVoiceResult(text, isFinal) {
      if (typeof text !== 'string') return;
      const base = S.micBase || '';
      const sep = base && !/\s$/.test(base) ? ' ' : '';
      input.value = base + sep + text;
      input.dispatchEvent(new Event('input'));
      if (isFinal) {
        S.listening = false;
        S.micBase = '';
        scheduleRender();
      }
    }

    function voiceFailed(message) {
      S.listening = false;
      S.micBase = '';
      if (message) ctx.ui.toast(message);
      scheduleRender();
    }

    if (window.antiSIT && typeof window.antiSIT.on === 'function') {
      window.antiSIT.on('voice.result', (data) => {
        if (!S.alive || !data) return;
        applyVoiceResult(String(data.text || ''), !!data.isFinal);
      });
      window.antiSIT.on('voice.error', (data) => {
        if (!S.alive) return;
        voiceFailed(String((data && data.message) || '语音识别失败'));
      });
    }

    async function toggleMic() {
      if (!S.micReady) {
        ctx.ui.toast('这台设备没有可用的语音识别服务');
        return;
      }
      if (S.listening) {
        S.listening = false;
        scheduleRender();
        try {
          await ctx.voice.stop();
        } catch (_) {}
        return;
      }
      S.micBase = input.value;
      S.listening = true;
      scheduleRender();
      try {
        const ok = await ctx.voice.start();
        if (!ok) voiceFailed('没能开始录音：检查麦克风权限');
      } catch (e) {
        voiceFailed((e && e.message) || '语音输入不可用');
      }
    }
    notify = () => {
      if (S.alive) render();
    };

    function scheduleRender() {
      if (!S.alive || renderScheduled) return;
      renderScheduled = true;
      setTimeout(() => {
        renderScheduled = false;
        if (S.alive) render();
      }, 0);
    }
    onSessionChange = scheduleRender;

    function render() {
      if (!S.alive) return;
      const draft = S.draft;
      const conv = (S.conversations || []).find((c) => c.id === S.conversationId);
      $('#convTitle').textContent = (conv && conv.title) || '新对话';
      $('#draftMeta').textContent = draft
        ? draft.name + ' · v' + draft.version + (draft.installed ? ' · 已安装' : '')
        : '还没有拓展';

      $('#btnPlan').classList.toggle('active', !!S.planMode);
      $('#btnPlan').disabled = S.running;
      $('#btnFull').classList.toggle('active', !!S.fullAccess);
      $('#btnFull').disabled = S.running;

      const modelBtn = $('#btnModel');
      modelBtn.textContent = S.model ? shortModel(S.model) : '模型';
      modelBtn.classList.toggle('active', !!S.model);
      const effortBtn = $('#btnEffort');
      effortBtn.textContent = S.effort ? EFFORT_LABELS[S.effort] || '思考' : '思考';
      effortBtn.classList.toggle('active', !!S.effort);
      modelBtn.disabled = S.running;
      effortBtn.disabled = S.running;

      // 麦克风常驻（不再因为「没检测到识别服务」就消失）：按了才知道有没有，
      // 没有就给一句提示，而不是让按钮凭空不见、用户找不到。
      const micBtn = $('#btnMic');
      micBtn.classList.toggle('recording', !!S.listening);
      micBtn.setAttribute('aria-label', S.listening ? '停止录音' : '语音输入');
      micBtn.title = S.listening ? '停止录音' : '语音输入';
      // 录音时把发送收起来、换成停止：同一位置只留一个主动作，免得点错
      $('#btnSend').classList.toggle('hidden', S.running || !!S.listening);
      $('#btnSend').disabled = !S.session;
      $('#btnStop').classList.toggle('hidden', !(S.running || S.listening));
      const publishBtn = $('#btnPublish');
      if (publishBtn) publishBtn.disabled = S.running || !draft;
      $('#btnStop').classList.toggle('hidden', !S.running);
      input.placeholder = S.running
        ? '可以继续输入，下一步会看到'
        : S.planMode
          ? '计划模式：只读分析，先给方案'
          : '说说要做什么，或者打 / 挑工具、挑技能';

      const queued = S.inbox.nextTurn.length + S.inbox.nextStep.length;
      const metaLine = $('#metaLine');
      metaLine.classList.toggle('running', !!S.running);
      metaLine.textContent = S.running
        ? (S.status || '处理中…') + (queued ? ' · 已排队 ' + queued + ' 条' : '')
        : [
            (S.conversations || []).length + ' 条对话',
            S.files.length + ' 个文件',
            S.planMode ? '计划模式' : (S.fullAccess ? '完全访问' : '自动确认'),
          ].join(' · ');
      status.classList.add('hidden');
      status.textContent = '';

      $('#filesCount').textContent = S.files.length + ' 个文件';

      renderChat();
      renderFiles();
      if (!switchSheet.classList.contains('hidden')) renderSwitch();
      if (!modelSheet.classList.contains('hidden')) renderModels();
      if (!skillsDrawer.classList.contains('hidden')) renderSkills();
    }


// ==================== 模型 / 思考深度 ====================

/** 思考档位：key 是发给宿主的值，label 是按钮上的字。 */
const EFFORTS = [
  ['', '默认'],
  ['none', '不思考'],
  ['low', '浅'],
  ['medium', '中'],
  ['high', '深'],
];
const EFFORT_LABELS = { none: '不思考', low: '浅思考', medium: '中思考', high: '深思考' };

/** 按钮上只放模型名的尾巴（deepseek-v4-pro → v4-pro），省位置。 */
function shortModel(id) {
  const parts = String(id || '').split(/[\/-]/).filter(Boolean);
  const tail = parts.length > 1 ? parts[parts.length - 1] : (parts[0] || id);
  return tail.length > 12 ? tail.slice(0, 12) + '…' : tail;
}

/** 拉一次模型清单 + 当前值（进工坊 / 打开面板时各调一次）。 */
async function refreshModelState() {
  try {
    const info = await ctx.ai.current();
    if (!S.alive) return;
    S.model = String((info && info.model) || '');
    const list = await ctx.ai.models();
    if (!S.alive) return;
    const arr = (list && list.models) || [];
    S.models = arr.map((m) => String(m));
    if (!S.model && S.models.length) S.model = S.models[0];
  } catch (e) {
    // AI 没配好（没 Key / 没选提供商）时这里会抛：按钮就当「未配置」，别弹错误
    S.model = '';
    S.models = [];
  }
  scheduleRender();
}

/** 模型面板：思考档位 + 模型列表，点一下即生效。 */
function renderModels() {
  const effortBox = $('#effortList');
  effortBox.innerHTML = '';
  for (const [value, label] of EFFORTS) {
    const b = document.createElement('button');
    b.className = 'pick' + (S.effort === value ? ' active' : '');
    b.innerHTML = '<span class="pick-main"><strong>' + esc(label) + '</strong></span>';
    b.addEventListener('click', async () => {
      S.effort = value;
      await ctx.storage.set('reasoning_effort', value);
      scheduleRender();
    });
    effortBox.appendChild(b);
  }
  const modelBox = $('#modelList');
  modelBox.innerHTML = '';
  if (!S.models.length) {
    const empty = document.createElement('div');
    empty.className = 'sheet-label';
    empty.textContent = '没读到可用模型：先到「我的 → AI 设置」配好提供商与 Key';
    modelBox.appendChild(empty);
    return;
  }
  for (const id of S.models) {
    const b = document.createElement('button');
    b.className = 'pick' + (S.model === id ? ' active' : '');
    b.innerHTML = '<span class="pick-main"><strong>' + esc(id) + '</strong></span>';
    b.addEventListener('click', async () => {
      b.disabled = true;
      try {
        const r = await ctx.ai.setModel(id);
        S.model = String((r && r.model) || id);
        await ctx.storage.set('model', S.model);
      } catch (e) {
        ctx.ui.toast('换模型失败：' + ((e && e.message) || e));
      }
      b.disabled = false;
      scheduleRender();
    });
    modelBox.appendChild(b);
  }
}
    /** 「切换」面板：拓展列表 + 当前拓展的对话列表（点一下切过去）。 */
    function renderSwitch() {
      const draftBox = $('#draftList');
      draftBox.innerHTML = '';
      for (const d of S.drafts) {
        const b = document.createElement('button');
        b.className = 'pick' + (S.draft && d.id === S.draft.id ? ' active' : '');
        b.innerHTML = '<span class="pick-main"><strong>' + esc(d.name) + '</strong>'
          + '<em>v' + esc(d.version) + (d.installed ? ' · 已安装' : '') + '</em></span>'
          + '<span class="pick-check">' + (S.draft && d.id === S.draft.id ? '<svg viewBox="0 0 24 24"><path d="M4 12l6 6L20 6"/></svg>' : '') + '</span>';
        b.disabled = S.running;
        b.addEventListener('click', async () => {
          closeOverlays();
          if (S.running || (S.draft && d.id === S.draft.id)) return;
          try {
            await selectDraft(d);
          } catch (e) {
            ctx.ui.toast('切换失败：' + (e && e.message ? e.message : e));
          }
        });
        draftBox.appendChild(b);
      }

      const convBox = $('#convList');
      convBox.innerHTML = '';
      for (const c of S.conversations) {
        const b = document.createElement('button');
        b.className = 'pick' + (c.id === S.conversationId ? ' active' : '');
        b.innerHTML = '<span class="pick-main"><strong>' + esc(c.title || '新对话') + '</strong>'
          + '<em>' + (c.updatedAt ? new Date(c.updatedAt).toLocaleString('zh-CN', { hour12: false }) : '') + '</em></span>'
          + '<span class="pick-check">' + (c.id === S.conversationId ? '<svg viewBox="0 0 24 24"><path d="M4 12l6 6L20 6"/></svg>' : '') + '</span>';
        b.disabled = S.running;
        b.addEventListener('click', async () => {
          closeOverlays();
          if (S.running || c.id === S.conversationId) return;
          try {
            await selectConversation(c.id);
          } catch (e) {
            ctx.ui.toast('切换对话失败：' + (e && e.message ? e.message : e));
          }
        });
        convBox.appendChild(b);
      }
      if (!S.conversations.length) {
        convBox.innerHTML = '<div class="empty">还没有对话</div>';
      }
    }

    function renderChat() {
      // 重建 DOM 前记住用户手动展开的思考 / 工具卡片，重建后恢复
      const openKeys = new Set();
      chat.querySelectorAll('details[open][data-key]').forEach((d) => {
        // 运行中的工具卡是自动展开的，不算用户选择；结束后回到收起
        if (d.classList.contains('running')) return;
        openKeys.add(d.getAttribute('data-key'));
      });
      const prevTop = chat.scrollTop;
      const atBottom =
        chat.scrollHeight - prevTop - chat.clientHeight < 48 || !chat.dataset.ready;
      chat.innerHTML = '';
      const streamText = S.textMode ? '' : ((S.stream && S.stream.text) || '');
      const streamReasoning = (S.stream && S.stream.reasoning) || '';
      if ((!S.session || !S.session.hasVisibleMessages())
          && !S.pending.length && !streamText && !streamReasoning) {
        chat.innerHTML = WELCOME;
        chat.querySelectorAll('[data-say]').forEach((button) => {
          button.addEventListener('click', () => {
            input.value = button.getAttribute('data-say');
            send();
          });
        });
        chat.dataset.ready = '1';
        return;
      }
      const items = S.session ? S.session.projectChat() : [];
      // 连续的工具调用收成一条「已执行 N 个操作」，点开看每个的参数与结果
      let tools = [];
      const flushTools = () => {
        if (!tools.length) return;
        chat.appendChild(toolRunEl(tools));
        tools = [];
      };
      for (const item of items) {
        if (item.role === 'tool') {
          tools.push(item);
          continue;
        }
        flushTools();
        chat.appendChild(messageEl(item));
      }
      flushTools();
      for (const message of S.pending) {
        const row = document.createElement('div');
        row.className = 'msg user pending';
        row.innerHTML = '<div class="bubble user">' + esc(message.text) + '</div>';
        chat.appendChild(row);
      }
      if (streamText || streamReasoning) {
        chat.appendChild(messageEl({
          role: 'assistant',
          text: streamText,
          reasoning: streamReasoning,
          streaming: true,
          key: 'stream',
        }));
      }
      if (openKeys.size) {
        chat.querySelectorAll('details[data-key]').forEach((d) => {
          if (openKeys.has(d.getAttribute('data-key'))) d.open = true;
        });
      }
      chat.dataset.ready = '1';
      if (atBottom) {
        chat.scrollTop = chat.scrollHeight;
      } else {
        chat.scrollTop = prevTop;
      }
    }

    /** 一组工具调用：默认一行（✓ 已执行 N 个操作），点开逐条看参数 / 结果。 */
    function toolRunEl(items) {
      const running = items.some((t) => t.running);
      const bad = items.some((t) => !t.running && !t.ok);
      const run = document.createElement('details');
      run.className = 'tool-run ' + (running ? 'running' : (bad ? 'bad' : 'ok'));
      run.setAttribute('data-key', (items[0].key || 'tools') + ':tools');
      if (running) run.open = true;
      const summary = document.createElement('summary');
      summary.innerHTML = '<span class="tool-dot"></span>'
        + '<span>' + esc(running
          ? '正在执行 ' + items.length + ' 个操作…'
          : bad ? '有操作失败' : '已执行 ' + items.length + ' 个操作') + '</span>'
        + '<span class="tool-chev"><svg viewBox="0 0 24 24"><path d="M9 5l7 7-7 7"/></svg></span>';
      run.appendChild(summary);
      const body = document.createElement('div');
      body.className = 'tool-list';
      for (const t of items) {
        const row = document.createElement('details');
        row.className = 'tool-item ' + (t.running ? 'running' : (t.ok ? 'ok' : 'bad'));
        if (t.key) row.setAttribute('data-key', t.key + ':tool');
        const head = document.createElement('summary');
        head.innerHTML = '<span class="tool-dot"></span><code>' + esc(t.name) + '</code>'
          + '<span class="tool-state">'
          + (t.running ? '执行中' : (t.ok ? '完成' : '失败')) + '</span>';
        row.appendChild(head);
        if (t.args) {
          const pre = document.createElement('pre');
          pre.textContent = t.args;
          row.appendChild(pre);
        }
        if (t.result) {
          const pre = document.createElement('pre');
          pre.className = 'result';
          pre.textContent = t.result;
          row.appendChild(pre);
        }
        body.appendChild(row);
      }
      run.appendChild(body);
      return run;
    }


    /** 目标卡：这条对话在做什么（Agent 用 set_goal 写的）。 */
    function goalEl(m) {
      const div = document.createElement('div');
      div.className = 'goal';
      div.innerHTML = '<span class="goal-tag">目标</span>'
        + '<span class="goal-text">' + esc(m.text) + '</span>';
      return div;
    }

    /** 计划卡：有序步骤 + 勾选状态，运行中一眼看到进行到哪。 */
    function planEl(m) {
      const steps = Array.isArray(m.steps) ? m.steps : [];
      const done = steps.filter((s) => s.status === 'completed').length;
      const div = document.createElement('div');
      div.className = 'plan';
      const head = document.createElement('div');
      head.className = 'plan-head';
      head.innerHTML = '<span class="plan-tag">计划</span>'
        + '<span>' + done + ' / ' + steps.length + '</span>';
      div.appendChild(head);
      const list = document.createElement('div');
      list.className = 'plan-list';
      for (const step of steps) {
        const row = document.createElement('div');
        row.className = 'plan-step ' + (step.status || 'pending');
        row.innerHTML = '<span class="plan-dot"></span>'
          + '<span class="plan-text">' + esc(step.content) + '</span>';
        list.appendChild(row);
      }
      div.appendChild(list);
      return div;
    }
    function messageEl(m) {
      if (m.role === 'goal') return goalEl(m);
      if (m.role === 'plan') return planEl(m);
      if (m.role === 'error') {
        const div = document.createElement('div');
        div.className = 'msg error';
        div.textContent = m.text;
        return div;
      }
      if (m.role === 'user') {
        const row = document.createElement('div');
        row.className = 'msg user';
        const bubble = document.createElement('div');
        bubble.className = 'bubble user';
        bubble.textContent = m.text;
        row.appendChild(bubble);
        return row;
      }
      const div = document.createElement('div');
      div.className = 'msg assistant' + (m.streaming ? ' streaming' : '');
      if (m.reasoning) {
        const details = document.createElement('details');
        details.className = 'think';
        if (m.key) details.setAttribute('data-key', m.key + ':think');
        const summary = document.createElement('summary');
        summary.textContent = m.streaming ? '深度思考中…' : '深度思考';
        details.appendChild(summary);
        const body = document.createElement('div');
        body.className = 'think-body';
        body.textContent = m.reasoning;
        details.appendChild(body);
        div.appendChild(details);
      }
      if (m.text) {
        const text = document.createElement('div');
        text.className = 'md';
        text.innerHTML = md(m.text);
        div.appendChild(text);
      }
      if (m.streaming && !m.text && !m.reasoning) {
        const wait = document.createElement('div');
        wait.className = 'md muted';
        wait.textContent = '…';
        div.appendChild(wait);
      }
      if (m.text && !m.streaming) {
        const foot = document.createElement('div');
        foot.className = 'msg-foot';
        foot.innerHTML = '<button class="msg-copy" data-copy>复制</button>';
        div.appendChild(foot);
      }
      return div;
    }

    function renderFiles() {
      const box = $('#files');
      box.innerHTML = '';
      if (!S.files.length) {
        box.innerHTML = '<div class="empty">还没有文件</div>';
        return;
      }
      for (const f of S.files) {
        const b = document.createElement('button');
        b.className = 'file';
        b.innerHTML = '<span>' + esc(f.path) + '</span><em>' + f.size + ' B</em>';
        b.addEventListener('click', () => openFile(f.path));
        box.appendChild(b);
      }
    }

    function renderSkills() {
      const box = $('#skills');
      box.innerHTML = '';
      if (!S.skills.length) {
        box.innerHTML = '<div class="empty">还没有安装技能。Agent 可以用 install_skill 安装。</div>';
        return;
      }
      for (const skill of S.skills) {
        const row = document.createElement('div');
        row.className = 'skill';
        const main = document.createElement('button');
        main.className = 'skill-main';
        main.innerHTML = '<strong>' + esc(skill.name) + '</strong>'
          + '<span>' + esc(skill.description || '（无说明）') + '</span>';
        main.addEventListener('click', () => openSkill(skill));
        const del = document.createElement('button');
        del.className = 'icon-btn danger';
        del.textContent = '删';
        del.title = '删除技能';
        del.addEventListener('click', async () => {
          try {
            const result = await ctx.workshop.deleteSkill(skill.id, true);
            if (result && result.denied) return;
            await refreshSkills();
            renderSkills();
            ctx.ui.toast('技能已删除');
          } catch (e) {
            ctx.ui.toast('删除失败：' + (e && e.message ? e.message : e));
          }
        });
        row.appendChild(main);
        row.appendChild(del);
        box.appendChild(row);
      }
    }



    // ---------- MCP 服务器（用户自己填的远程 JSON-RPC 端点） ----------

    let mcpServers = [];

    function renderMcp() {
      const box = $('#mcpList');
      box.innerHTML = '';
      if (!mcpServers.length) {
        box.innerHTML = '<div class="empty">还没有 MCP 服务器。填一个 http(s) 地址点「添加」。</div>';
        return;
      }
      for (const server of mcpServers) {
        const row = document.createElement('div');
        row.className = 'skill';
        const main = document.createElement('div');
        main.className = 'skill-main';
        main.innerHTML = '<strong>' + esc(server.name || server.id) + '</strong>'
          + '<span>' + esc(server.url) + '</span>';
        const del = document.createElement('button');
        del.className = 'icon-btn danger';
        del.textContent = '删';
        del.title = '删除这台服务器';
        del.addEventListener('click', async () => {
          try {
            const r = await ctx.workshop.removeMcp(server.id);
            mcpServers = (r && r.servers) || [];
            renderMcp();
            await refreshMcpTools();
          } catch (e) {
            ctx.ui.toast('删除失败：' + ((e && e.message) || e));
          }
        });
        row.appendChild(main);
        row.appendChild(del);
        box.appendChild(row);
      }
    }

    /** 列工具：一台一台连（失败的那台单独标红，不拖垮别的）。 */
    async function refreshMcpTools() {
      const box = $('#mcpTools');
      box.innerHTML = '<div class="empty">正在连接…</div>';
      let result;
      try {
        result = await ctx.workshop.mcpTools();
      } catch (e) {
        box.innerHTML = '<div class="empty">连接失败：' + esc((e && e.message) || String(e)) + '</div>';
        return;
      }
      const servers = (result && result.servers) || [];
      if (!servers.length) {
        box.innerHTML = '<div class="empty">没有启用的服务器</div>';
        return;
      }
      box.innerHTML = '';
      for (const s of servers) {
        const head = document.createElement('div');
        head.className = 'sheet-label';
        head.textContent = (s.server || s.serverId) + (s.error ? ' · 连接失败' : '');
        box.appendChild(head);
        if (s.error) {
          const err = document.createElement('div');
          err.className = 'empty';
          err.textContent = s.error;
          box.appendChild(err);
          continue;
        }
        for (const tool of (s.tools || [])) {
          const row = document.createElement('div');
          row.className = 'skill';
          const main = document.createElement('div');
          main.className = 'skill-main';
          main.innerHTML = '<strong>' + esc(tool.name) + '</strong>'
            + '<span>' + esc(tool.description || '（无说明）') + '</span>';
          row.appendChild(main);
          box.appendChild(row);
        }
      }
    }


    /** 解析 mcpServers 配置：只收 http(s) 的，stdio / command 那类跳过。 */
    function parseMcpConfig(raw) {
      const text = String(raw || '').trim();
      if (!text) return [];
      let json = null;
      try {
        json = JSON.parse(text);
          } catch (_) {
        // 从聊天软件里复制过来的常常带说明文字：截取最外层的一对大括号再试
        const start = text.indexOf('{');
        const end = text.lastIndexOf('}');
        if (start >= 0 && end > start) {
          try {
            json = JSON.parse(text.slice(start, end + 1));
          } catch (_) {}
        }
      }
      if (!json) return [];
      const servers = json.mcpServers || json.mcp_servers || json.servers || json;
      if (!servers || typeof servers !== 'object') return [];
      const out = [];
      for (const [name, value] of Object.entries(servers)) {
        if (!value || typeof value !== 'object') continue;
        const url = value.url || value.serverUrl || value.endpoint || '';
        if (typeof url !== 'string' || !/^https?:\/\//i.test(url)) continue;
        const headers = {};
        if (value.headers && typeof value.headers === 'object') {
          for (const [k, v] of Object.entries(value.headers)) {
            if (typeof v === 'string') headers[k] = v;
          }
        }
        out.push({ name: String(name), url: url, headers: headers });
      }
      return out;
    }
    async function refreshMcpServers() {
      try {
        const r = await ctx.workshop.listMcp();
        mcpServers = (r && r.servers) || [];
      } catch (e) {
        mcpServers = [];
      }
      renderMcp();
    }
    // ---------- 技能导入（SKILL.md / 粘贴） ----------

    /** 从一段 SKILL.md 里抠出名字与说明：YAML 头的 name / description 优先。 */
    function parseSkillMarkdown(raw, fallbackName) {
      let text = String(raw || '').replace(/\r\n/g, '\n');
      let name = '';
      let description = '';
      const front = text.match(/^---\n([\s\S]*?)\n---\n?/);
      if (front) {
        const head = front[1];
        const nm = head.match(/^name:\s*(.+)$/m);
        if (nm) name = nm[1].trim().replace(/^["']|["']$/g, '');
        const dm = head.match(/^description:\s*(.+)$/m);
        if (dm) description = dm[1].trim().replace(/^["']|["']$/g, '');
        text = text.slice(front[0].length);
      }
      if (!name) {
        const h1 = text.match(/^#\s+(.+)$/m);
        if (h1) name = h1[1].trim();
      }
      if (!name) name = fallbackName || '未命名技能';
      if (!description) {
        // 头里没有说明：取正文第一段非空、非标题的行
        const lines = text.split('\n').map((l) => l.trim());
        for (const line of lines) {
          if (!line || line.startsWith('#')) continue;
          description = line.slice(0, 120);
          break;
        }
      }
      return { name: name.slice(0, 40), description: description.slice(0, 160), content: text.trim() };
    }

    /** 装一条技能（走宿主 workshop.skills.install，带确认框）。 */
    async function installSkillText(title, content) {
      if (!String(content || '').trim()) {
        ctx.ui.toast('内容为空，没装');
        return;
      }
      S.status = '等待确认安装技能…';
      notify();
      try {
        const result = await ctx.workshop.installSkill(title.name, title.description, content);
        if (result && result.denied) return;
        if (!result || result.ok !== true) throw new Error('技能安装失败');
        await refreshSkills();
        renderSkills();
        ctx.ui.toast('已安装技能「' + (result.name || title.name) + '」');
      } catch (e) {
        ctx.ui.toast('安装失败：' + ((e && e.message) || e));
      } finally {
        S.status = '';
        notify();
      }
    }

    async function importSkillFromFile() {
      try {
        const picked = await ctx.files.pick({ accept: ['.md', '.markdown', '.txt'], encoding: 'text' });
        const file = (picked && picked.files && picked.files[0]) || null;
        if (!file) return;
        const raw = typeof file.text === 'string' ? file.text : '';
        const parsed = parseSkillMarkdown(raw, String(file.name || '').replace(/\.(md|markdown|txt)$/i, ''));
        await installSkillText(parsed, parsed.content);
      } catch (e) {
        ctx.ui.toast('读取文件失败：' + ((e && e.message) || e));
      }
    }

    async function importSkillFromText() {
      // WebView 里没有 window.prompt（会被直接吞掉）：用页面自己的多行输入弹层
      const raw = await askLongText('粘贴 SKILL.md 的内容', '第一段可以是 --- name / description --- 头');
      if (raw == null) return;
      const parsed = parseSkillMarkdown(raw, '粘贴的技能');
      await installSkillText(parsed, parsed.content);
    }
    async function openSkill(skill) {
      try {
        const result = await ctx.workshop.readSkill(skill.id);
        showViewer('技能 · ' + skill.name, String((result && result.content) || ''));
      } catch (e) {
        ctx.ui.toast('读取技能失败：' + (e && e.message ? e.message : e));
      }
    }

    function showViewer(title, content) {
      $('#viewerTitle').textContent = title;
      $('#viewerBody').textContent = content;
      viewer.classList.remove('hidden');
      backdrop.classList.remove('hidden');
    }

    async function openFile(path) {
      try {
        const read = normalizeRead(await ctx.workshop.read(S.draft.id, path));
        showViewer(path, read.content);
      } catch (e) {
        ctx.ui.toast('打开失败：' + (e && e.message ? e.message : e));
      }
    }

    function closeOverlays() {
      switchSheet.classList.add('hidden');
      modelSheet.classList.add('hidden');
      mcpDrawer.classList.add('hidden');
      skillsDrawer.classList.add('hidden');
      moreMenu.classList.add('hidden');
      backdrop.classList.add('hidden');
      viewer.classList.add('hidden');
    }

    /** 页签：对话 / 文件（DSH 那种顶栏下划线页签）。 */
    function setTab(tab) {
      S.tab = tab;
      root.querySelectorAll('.ws-tab').forEach((b) => {
        b.classList.toggle('active', b.getAttribute('data-tab') === tab);
      });
      chat.classList.toggle('hidden', tab !== 'chat');
      filesPanel.classList.toggle('hidden', tab !== 'files');
      if (tab === 'files') {
        refreshFiles().then(() => {
          if (S.alive) {
            $('#filesCount').textContent = S.files.length + ' 个文件';
            renderFiles();
          }
        }).catch(() => {});
      }
    }

    function send() {
      const text = input.value.trim();
      if (!text || !S.session) return;
      input.value = '';
      input.style.height = '';
      S.slashOpen = false;
      S.slashItems = [];
      renderSlash();
      const message = { text: text };
      const target = S.running ? 'next-step' : 'next-turn';
      S.pending.push(message);
      S.inbox.push(target, message);
      notify();
      if (!S.running) runAgent();
    }


    // ---------- 「/」命令面板：调用工具与技能 ----------

    /** 候选项：工具（带说明）+ 技能（带说明），按 query 前缀 / 包含过滤。 */
    function slashCandidates(query) {
      const q = String(query || '').toLowerCase();
      const tools = availableTools().map((tool) => {
        const label = TOOL_UI_LABELS[tool.name] || [tool.name, ''];
        return {
          kind: 'tool',
          // 面板上显示中文名，插入时用真正的工具名（模型只认后者）
          name: label[0],
          hint: label[1],
          insert: tool.name,
          toolName: tool.name,
        };
      });
      const skills = ((S && S.skills) || []).map((skill) => ({
        kind: 'skill',
        name: skill.name,
        hint: skill.description || '（无说明）',
        insert: '用 read_skill 读「' + skill.name + '」并按它的说明做：',
      }));
      const all = tools.concat(skills);
      if (!q) return all.slice(0, 12);
      return all
        .filter((item) => item.name.toLowerCase().indexOf(q) >= 0
          || item.hint.toLowerCase().indexOf(q) >= 0)
        .slice(0, 12);
    }

    function renderSlash() {
      const panel = $('#slashPanel');
      if (!S.slashOpen || !S.slashItems.length) {
        panel.classList.add('hidden');
        panel.innerHTML = '';
        return;
      }
      panel.classList.remove('hidden');
      panel.innerHTML = '';
      S.slashItems.forEach((item, i) => {
        const row = document.createElement('button');
        row.className = 'slash-item' + (i === S.slashIndex ? ' active' : '');
        row.innerHTML = '<span class="slash-kind ' + item.kind + '">'
          + (item.kind === 'tool' ? '工具' : '技能') + '</span>'
          + '<span class="slash-main"><strong>' + esc(item.name) + '</strong>'
          + (item.kind === 'tool'
            ? '<em>' + esc(item.toolName) + ' · ' + esc(item.hint) + '</em>'
            : '<em>' + esc(item.hint) + '</em>')
          + '</span>';
        // 用 mousedown 而不是 click：click 会在 textarea 失焦之后才触发
        row.addEventListener('mousedown', (e) => {
          e.preventDefault();
          applySlash(S.slashIndex = i);
        });
        panel.appendChild(row);
      });
    }

    /** 选中一条：工具补成「工具名 + 空格」，技能补成一句「读这条技能再照做」。 */
    function applySlash(index) {
      const item = S.slashItems[index];
      if (!item) return;
      // 工具补成真正的工具名（模型只认它），面板上显示的是中文名
      input.value = item.kind === 'tool'
        ? item.insert + ' '
        : item.insert;
      S.slashOpen = false;
      S.slashItems = [];
      renderSlash();
      input.focus();
      const end = input.value.length;
      input.setSelectionRange(end, end);
      input.dispatchEvent(new Event('input'));
    }

    /** 输入变化：以 / 开头（且还没打空格）就当在敲命令，刷新候选。 */
    function syncSlash() {
      const value = input.value;
      const atStart = value.startsWith('/') && !value.slice(1).includes(' ');
      if (!atStart) {
        if (S.slashOpen) {
          S.slashOpen = false;
          S.slashItems = [];
          renderSlash();
        }
        return;
      }
      const query = value.slice(1);
      S.slashQuery = query;
      S.slashItems = slashCandidates(query);
      S.slashIndex = 0;
      S.slashOpen = S.slashItems.length > 0;
      renderSlash();
    }
    S.syncSlash = syncSlash;

    // ==================== 事件 ====================

    $('#btnSend').addEventListener('click', send);
    $('#btnStop').addEventListener('click', () => {
      // 录音中按停止 = 结束这一轮识别；Agent 运行中按停止 = 中断本轮
      if (S.listening) {
        S.listening = false;
        scheduleRender();
        ctx.voice.stop().catch(() => {});
        return;
      }
      if (!S.running) return;
      S.abort.abort();
      S.inbox.clear();
      if (S.pending.length) {
        input.value = S.pending.map((m) => m.text).join('\n');
        S.pending = [];
      }
      S.status = '正在停止…';
      notify();
    });
    input.addEventListener('keydown', (e) => {
      // 命令面板打开时，上下键在候选里移动、回车选中；Esc 收起
      if (S.slashOpen) {
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          e.preventDefault();
          const delta = e.key === 'ArrowDown' ? 1 : -1;
          const n = S.slashItems.length;
          S.slashIndex = ((S.slashIndex + delta) % n + n) % n;
          renderSlash();
          return;
        }
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          applySlash(S.slashIndex);
          return;
        }
        if (e.key === 'Escape') {
          e.preventDefault();
          S.slashOpen = false;
          S.slashItems = [];
          renderSlash();
          return;
        }
      }
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        send();
      }
    });
    // 输入框跟着内容长高（最多 132px，再多就内部滚动）
    input.addEventListener('input', () => {
      input.style.height = 'auto';
      input.style.height = Math.min(input.scrollHeight, 132) + 'px';
      syncSlash();
    });

    // ---- 重命名：页面内的输入弹层（WebView 里没法用原生输入框）----
    let promptResolve = null;
    function askText(title, initial, maxLength) {
      $('#promptTitle').textContent = title;
      const field = $('#promptInput');
      field.maxLength = maxLength || 48;
      field.value = initial || '';
      $('#prompt').classList.remove('hidden');
      setTimeout(() => {
        field.focus();
        field.select();
      }, 0);
      return new Promise((resolve) => {
        promptResolve = resolve;
      });
    }
    function closePrompt(value) {
      $('#prompt').classList.add('hidden');
      const resolve = promptResolve;
      promptResolve = null;
      if (resolve) resolve(value);
    }
    $('#promptCancel').addEventListener('click', () => closePrompt(null));
    $('#promptOk').addEventListener('click', () => closePrompt($('#promptInput').value.trim()));
    $('#promptInput').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        closePrompt($('#promptInput').value.trim());
      } else if (e.key === 'Escape') {
        closePrompt(null);
      }
    });
    $('#prompt').addEventListener('click', (e) => {
      if (e.target === $('#prompt')) closePrompt(null);
    });

    // ---- 长文本输入（粘贴导入技能用；单行输入框装不下整份 SKILL.md）----
    let pasteResolve = null;
    function askLongText(title, hint) {
      $('#pasteTitle').textContent = title;
      const field = $('#pasteInput');
      field.value = '';
      field.placeholder = hint || '粘贴内容…';
      $('#pastePanel').classList.remove('hidden');
      setTimeout(() => field.focus(), 0);
      return new Promise((resolve) => {
        pasteResolve = resolve;
      });
    }
    function closePaste(value) {
      $('#pastePanel').classList.add('hidden');
      const resolve = pasteResolve;
      pasteResolve = null;
      if (resolve) resolve(value);
    }
    $('#pasteCancel').addEventListener('click', () => closePaste(null));
    $('#pasteOk').addEventListener('click', () => closePaste($('#pasteInput').value));
    $('#pastePanel').addEventListener('click', (e) => {
      if (e.target === $('#pastePanel')) closePaste(null);
    });

    async function renameCurrentDraft() {
      if (!S.draft || S.running) return;
      const name = await askText('重命名拓展', S.draft.name, 20);
      if (!name || name === S.draft.name) return;
      try {
        const updated = await ctx.workshop.renameDraft(S.draft.id, name);
        S.draft = updated;
        await refreshDraftList();
        notify();
        ctx.ui.toast('拓展已重命名');
      } catch (e) {
        ctx.ui.toast('重命名失败：' + (e && e.message ? e.message : e));
      }
    }

    async function renameCurrentConversation() {
      if (!S.draft || !S.conversationId || S.running) return;
      const current = (S.conversations || []).find((c) => c.id === S.conversationId);
      const title = await askText('重命名对话', (current && current.title) || '新对话', 48);
      if (!title || (current && title === current.title)) return;
      try {
        const renamed = await ctx.workshop.renameConversation(
            S.draft.id, S.conversationId, title);
        if (S.session) S.session.title = renamed.title;
        await refreshConversations();
        notify();
        ctx.ui.toast('对话已重命名');
      } catch (e) {
        ctx.ui.toast('重命名失败：' + (e && e.message ? e.message : e));
      }
    }

    // ---- 切换面板 / 页签 / 更多菜单 ----
    const openSwitch = () => {
      if (S.running) {
        ctx.ui.toast('Agent 运行中，先停止再切换');
        return;
      }
      renderSwitch();
      switchSheet.classList.remove('hidden');
      skillsDrawer.classList.add('hidden');
      backdrop.classList.remove('hidden');
    };
    $('#btnSwitch').addEventListener('click', openSwitch);
    // 标题区现在只是文本（不再是按钮）：点它也能开切换面板
    $('.ws-heading').addEventListener('click', openSwitch);

    root.querySelectorAll('.ws-tab').forEach((b) => {
      b.addEventListener('click', () => setTab(b.getAttribute('data-tab')));
    });
    $('#btnRefreshFiles').addEventListener('click', () => setTab('files'));

    $('#btnPublish').addEventListener('click', async () => {
      if (S.running || !S.draft) return;
      try {
        await ctx.workshop.publish(S.draft.id);
      } catch (err) {
        ctx.ui.toast('打开发布页失败：' + (err && err.message ? err.message : err));
      }
    });

    $('#btnMore').addEventListener('click', (e) => {
      e.stopPropagation();
      const open = moreMenu.classList.contains('hidden');
      moreMenu.classList.toggle('hidden', !open);
      if (!open) return;
      moreMenu.querySelectorAll('button').forEach((b) => {
        const act = b.getAttribute('data-act');
        const needsDraft = act === 'install' || act === 'preview' || act === 'publish'
          || act === 'newConv'
          || act === 'deleteConv' || act === 'deleteDraft'
          || act === 'renameConv' || act === 'renameDraft';
        b.disabled = S.running
          || (needsDraft && !S.draft)
          || (act === 'renameConv' && !S.conversationId)
          || (act === 'deleteDraft' && S.draft && !!S.draft.installed);
      });
    });

    moreMenu.addEventListener('click', async (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      const act = b.getAttribute('data-act');
      moreMenu.classList.add('hidden');
      const draft = S.draft;
      try {
        if (act === 'mcp') {
          await refreshMcpServers();
          mcpDrawer.classList.remove('hidden');
          skillsDrawer.classList.add('hidden');
          switchSheet.classList.add('hidden');
          backdrop.classList.remove('hidden');
          renderMcp();
          refreshMcpTools();
        } else if (act === 'skills') {
          await refreshSkills();
          skillsDrawer.classList.remove('hidden');
          switchSheet.classList.add('hidden');
          backdrop.classList.remove('hidden');
          renderSkills();
        } else if (act === 'preview') {
          if (draft) await ctx.workshop.preview(draft.id);
        } else if (act === 'install') {
          if (!draft) return;
          const result = await ctx.workshop.install(draft.id);
          if (result && result.denied) return;
          ctx.ui.toast('已安装，可在「拓展」页打开');
          await refreshDraftList();
          notify();
        } else if (act === 'publish') {
          if (!draft) return;
          await ctx.workshop.publish(draft.id);
        } else if (act === 'newConv') {
          await newConversation();
          ctx.ui.toast('已新建对话');
        } else if (act === 'newDraft') {
          if (S.session) await S.session.flush();
          const created = await ctx.workshop.create('未命名拓展');
          await refreshDraftList();
          S.drafts = [created].concat(S.drafts.filter((d) => d.id !== created.id));
          await selectDraft(created);
          ctx.ui.toast('已新建拓展');
        } else if (act === 'renameConv') {
          await renameCurrentConversation();
        } else if (act === 'renameDraft') {
          await renameCurrentDraft();
        } else if (act === 'deleteConv') {
          await deleteCurrentConversation();
        } else if (act === 'deleteDraft') {
          await deleteCurrentDraft();
        }
      } catch (err) {
        ctx.ui.toast('操作失败：' + (err && err.message ? err.message : err));
      }
    });

    // 点空白处收起更多菜单
    root.addEventListener('click', (e) => {
      if (!moreMenu.classList.contains('hidden')
          && !moreMenu.contains(e.target)
          && !e.target.closest('#btnMore')) {
        moreMenu.classList.add('hidden');
      }
    });

    // 代码块 / 消息的「复制」
    chat.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-copy]');
      if (!btn) return;
      const code = btn.closest('.code');
      if (code) {
        const pre = code.querySelector('code');
        copyText(pre ? pre.textContent : '');
        return;
      }
      const msg = btn.closest('.msg');
      const body = msg && msg.querySelector('.md');
      copyText(body ? body.innerText : '');
    });

    $('#btnModel').addEventListener('click', () => {
      modelSheet.classList.toggle('hidden');
      backdrop.classList.toggle('hidden', modelSheet.classList.contains('hidden'));
      if (!modelSheet.classList.contains('hidden')) {
        renderModels();
        refreshModelState();
      }
    });
    $('#btnCloseModel').addEventListener('click', () => {
      modelSheet.classList.add('hidden');
      backdrop.classList.add('hidden');
    });
    $('#btnEffort').addEventListener('click', () => {
      modelSheet.classList.toggle('hidden');
      backdrop.classList.toggle('hidden', modelSheet.classList.contains('hidden'));
      if (!modelSheet.classList.contains('hidden')) {
        renderModels();
        refreshModelState();
      }
    });
    $('#btnMic').addEventListener('click', toggleMic);
    $('#btnPlan').addEventListener('click', async () => {
      if (S.running) return;
      S.planMode = !S.planMode;
      try {
        await ctx.storage.set('plan_mode', S.planMode);
      } catch (_) {}
      // 不弹 toast：它挂在页面底部会盖住输入框；胶囊与底栏小字已经能看出状态
      notify();
    });
    $('#btnFull').addEventListener('click', async () => {
      if (S.running) return;
      try {
        if (S.fullAccess) {
          await ctx.workshop.setFullAccess(false);
          S.fullAccess = false;
          notify();
          return;
        }
        const result = await ctx.workshop.setFullAccess(true);
        if (result && result.ok && result.enabled === true) {
          S.fullAccess = true;
          notify();
        }
      } catch (e) {
        ctx.ui.toast('切换完全访问失败：' + (e && e.message ? e.message : e));
      }
    });
    $('#btnCloseMcp').addEventListener('click', closeOverlays);
    $('#btnAddMcp').addEventListener('click', async () => {
      const url = $('#mcpUrl').value.trim();
      if (!url) return;
      const auth = $('#mcpAuth').value.trim();
      const headers = {};
      if (auth) headers.Authorization = auth;
      try {
        const r = await ctx.workshop.addMcp({ url: url, headers: headers });
        mcpServers = (r && r.servers) || [];
        $('#mcpUrl').value = '';
        $('#mcpAuth').value = '';
        renderMcp();
        ctx.ui.toast('已添加，正在列工具…');
        await refreshMcpTools();
      } catch (e) {
        ctx.ui.toast('添加失败：' + ((e && e.message) || e));
      }
    });
    // 粘贴常见 MCP 配置：{"mcpServers":{"name":{"url":..., "headers":...}}}
    $('#btnPasteMcp').addEventListener('click', async () => {
      let raw = '';
      try {
        raw = (await ctx.clipboard.read()) || '';
      } catch (e) {
        ctx.ui.toast('读剪贴板失败：' + ((e && e.message) || e));
        return;
      }
      const parsed = parseMcpConfig(raw);
      if (!parsed.length) {
        ctx.ui.toast('剪贴板里没有能识别的 MCP 配置');
        return;
      }
      let added = 0;
      for (const entry of parsed) {
        try {
          const r = await ctx.workshop.addMcp({
            url: entry.url,
            name: entry.name,
            headers: entry.headers,
          });
          mcpServers = (r && r.servers) || mcpServers;
          added += 1;
        } catch (e) {
          ctx.ui.toast('「' + entry.name + '」添加失败：' + ((e && e.message) || e));
        }
      }
      renderMcp();
      ctx.ui.toast('已添加 ' + added + ' 台服务器');
      if (added) await refreshMcpTools();
    });
    $('#btnCloseSkills').addEventListener('click', closeOverlays);
    $('#btnImportSkillFile').addEventListener('click', importSkillFromFile);
    $('#btnImportSkillText').addEventListener('click', importSkillFromText);
    $('#btnCloseViewer').addEventListener('click', closeOverlays);
    backdrop.addEventListener('click', closeOverlays);

    ctx.effect(() => () => {
      S.alive = false;
      if (S.abort) S.abort.abort();
      S.inbox.clear();
      if (S.session) S.session.flush();
    }, 'workshop.cleanup');

    try {
      try {
        S.planMode = (await ctx.storage.get('plan_mode')) === true;
      } catch (_) {}
      try {
        const savedEffort = await ctx.storage.get('reasoning_effort');
        if (typeof savedEffort === 'string') S.effort = savedEffort;
      } catch (_) {}
      await refreshModelState();
      try {
        S.micReady = !!(await ctx.voice.available());
      } catch (_) {
        S.micReady = false;
      }
      await refreshSkills();
      await refreshDrafts();
      render();
    } catch (e) {
      const text = '工坊启动失败：' + (e && e.message ? e.message : e);
      if (S.session) {
        S.session.append('error', { text: text });
        render();
      } else {
        root.innerHTML = '<pre class="antisit-error">' + esc(text) + '</pre>';
      }
    }
  },
};
