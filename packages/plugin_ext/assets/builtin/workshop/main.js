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

const WELCOME = `
  <div class="welcome">
    <div class="spark">✨</div>
    <h2>和 Agent 一起写一个 Cordis 拓展</h2>
    <p>描述你想要的小工具。Agent 会先看草稿、读文件、再改；写文件和安装前都会弹确认。运行中也可以继续插话，下一步会看到。</p>
    <button data-say="做一个记录喝水次数的小工具，数据要留在本机">做一个喝水记录小工具</button>
    <button data-say="做一个倒计时，可以设定目标日期">做一个倒计时</button>
    <button data-say="先读一下当前 main.js，告诉我它是做什么的">读一下当前 main.js</button>
  </div>`;

// ==================== 会话日志 ====================

class AgentSession {
  constructor(vault, draftId, onChange) {
    this.vault = vault;
    this.draftId = draftId;
    this.onChange = onChange;
    this.events = [];
    this.seq = 0;
    this.turnSeq = 0;
    this.observed = new Map();
    this.dirty = false;
    this.timer = null;
    this.saving = null;
  }

  static async load(vault, draftId, onChange) {
    const session = new AgentSession(vault, draftId, onChange);
    let raw = null;
    try {
      raw = await vault.loadSession(draftId);
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
    if (event.type === 'file/observed') {
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
      await this.vault.saveSession(this.draftId, payload);
    } catch (e) {
      this.dirty = true;
      console.warn('[workshop] 会话日志保存失败', e);
    }
  }

  serialize() {
    return JSON.stringify({
      version: 1,
      draftId: this.draftId,
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
      if (event.type === 'user/message') {
        if (event.source === 'user') out.push({ role: 'user', text: event.content || '' });
      } else if (event.type === 'assistant/message') {
        if (event.text && !event.hidden) out.push({ role: 'assistant', text: event.text });
      } else if (event.type === 'tool/call') {
        const card = {
          role: 'tool',
          name: event.name || 'tool',
          args: event.arguments || '',
          result: '',
          ok: true,
          running: true,
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
          });
        }
      } else if (event.type === 'error' && !event.hidden) {
        out.push({ role: 'error', text: event.text || '' });
      }
    }
    return out;
  }

  hasVisibleMessages() {
    return this.events.some((e) =>
      e.type === 'user/message' && e.source === 'user'
      || e.type === 'assistant/message' && e.text && !e.hidden
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
    name: 'tool-guidance',
    order: 200,
    text: () => [
      '## Tools',
      ...TOOL_DEFS.map((tool) => '- ' + tool.name + ': ' + tool.prompt),
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
      'export default { name: "my-tool", inject: ["ui"], apply(ctx) { ctx.ui.root.innerHTML = "<h1>你好</h1>"; } };',
      '',
      'Available services after declaring them in inject:',
      '- ctx.ui: root, toast(text), close(), theme',
      '- ctx.storage: get/set/remove(key), Promise-based, isolated by extension id',
      '- ctx.card: setName/setDesc/setIcon',
      '- ctx.ai: chat(prompt, {system, maxTokens})',
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
      '- Do not load remote scripts or CSS. Prefer data: for images and fonts. Network access requires the network permission in ext.json and fetch.',
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
    name: 'list_files',
    readOnly: true,
    description: 'List every file in the current draft and its size.',
    prompt: 'list the current draft tree; call it before reading or editing.',
    parameters: { type: 'object', properties: {} },
    async run() {
      await refreshFiles();
      return S.files.length
        ? S.files.map((f) => f.path + '  ' + f.size + ' B').join('\n')
        : '（空草稿）';
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
];

function toolByName(name) {
  return TOOL_DEFS.find((tool) => tool.name === name);
}

function toolSpecs() {
  return TOOL_DEFS.map((tool) => ({
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
      content: 'Error: unknown tool "' + call.name + '". Available: ' + TOOL_DEFS.map((t) => t.name).join(', '),
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
    try {
      S.status = attempt === 1 ? '思考中…' : '模型请求失败，重试中…';
      notify();
      return await ctx.ai.chatTools({ messages: messages, tools: tools, maxTokens: 4096 });
    } catch (e) {
      lastError = e;
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

function appendAbortedReply(reply, turn, step) {
  if (!reply) return;
  const text = String(reply.text || '').trim();
  if (text) {
    S.session.append('assistant/message', {
      turn: turn,
      step: step,
      text: text,
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
    if (S.abort && S.abort.aborted) return abortReason();
    throw e;
  }
  if (S.abort && S.abort.aborted) {
    appendAbortedReply(reply, turn, step);
    return abortReason();
  }

  const wasTextMode = S.textMode;
  if (reply && reply.usedTools === false) S.textMode = true;
  const calls = wasTextMode ? [] : normalizeToolCalls(reply && reply.toolCalls);

  if (calls.length > 0) {
    S.session.append('assistant/message', {
      turn: turn,
      step: step,
      text: String((reply && reply.text) || ''),
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

  const text = String((reply && reply.text) || '').trim();
  if (!text) throw new Error('AI 没有给出内容，请重试');
  S.session.append('assistant/message', { turn: turn, step: step, text: text });
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
    await S.session.flush();
  }
}

function findLast(type) {
  for (let i = S.session.events.length - 1; i >= 0; i -= 1) {
    if (S.session.events[i].type === type) return S.session.events[i];
  }
  return null;
}

// ==================== 草稿 / 文件 ====================

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

async function selectDraft(draft) {
  if (S.session) await S.session.flush();
  S.draft = draft;
  S.inbox.clear();
  S.pending = [];
  S.textMode = false;
  S.files = [];
  S.session = await AgentSession.load(ctx.workshop, draft.id, onSessionChange);
  await refreshFiles();
  notify();
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
  const d = document.createElement('div');
  d.textContent = s == null ? '' : String(s);
  return d.innerHTML;
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
      session: null,
      inbox: new Inbox(),
      pending: [],
      running: false,
      abort: null,
      textMode: false,
      status: '',
      alive: true,
    };

    root.innerHTML = `
      <div class="ws">
        <header class="ws-head">
          <div class="ws-title">
            <div>
              <h1>拓展工坊</h1>
              <div class="ws-sub" id="draftMeta"></div>
            </div>
            <div class="ws-actions">
              <button id="btnFiles" title="草稿文件">文件</button>
              <button id="btnPreview" title="预览当前草稿">预览</button>
              <button id="btnInstall" class="primary" title="安装当前草稿">安装</button>
            </div>
          </div>
          <div class="ws-draftrow">
            <select id="draftSelect"></select>
            <button id="btnNew">新建</button>
          </div>
        </header>
        <main class="ws-chat" id="chat"></main>
        <div class="ws-status hidden" id="status"></div>
        <footer class="ws-foot">
          <textarea id="input" rows="1" placeholder="描述要做什么，或让我改哪个文件…"></textarea>
          <button id="btnSend" class="primary">发送</button>
          <button id="btnStop" class="hidden">停止</button>
        </footer>
        <div class="ws-drawer hidden" id="drawer">
          <div class="drawer-head">
            <strong>草稿文件</strong>
            <button id="btnCloseDrawer">关闭</button>
          </div>
          <div id="files"></div>
        </div>
        <div class="ws-backdrop hidden" id="backdrop"></div>
        <div class="ws-viewer hidden" id="viewer">
          <div class="viewer-head"><strong id="viewerTitle"></strong><button id="btnCloseViewer">关闭</button></div>
          <pre id="viewerBody"></pre>
        </div>
      </div>`;

    const $ = (sel) => root.querySelector(sel);
    const chat = $('#chat');
    const input = $('#input');
    const status = $('#status');
    const drawer = $('#drawer');
    const backdrop = $('#backdrop');
    const viewer = $('#viewer');
    let renderScheduled = false;

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
      $('#draftMeta').textContent = S.draft
        ? S.draft.name + ' · ' + S.draft.id + ' · v' + S.draft.version
        : '还没有草稿';
      const select = $('#draftSelect');
      select.innerHTML = S.drafts
        .map((d) => '<option value="' + esc(d.id) + '">' + esc(d.name) + '</option>')
        .join('');
      if (S.draft) select.value = S.draft.id;
      select.disabled = S.running || S.drafts.length <= 1;
      $('#btnNew').disabled = S.running;
      $('#btnInstall').disabled = S.running;
      $('#btnSend').classList.remove('hidden');
      $('#btnSend').disabled = !S.session;
      $('#btnStop').classList.toggle('hidden', !S.running);
      status.classList.toggle('hidden', !S.running);
      const queued = S.inbox.nextTurn.length + S.inbox.nextStep.length;
      status.textContent = (S.status || '处理中…') + (queued ? ' · 已排队 ' + queued + ' 条' : '');
      input.placeholder = S.running
        ? '可以继续输入，Agent 下一步会看到…'
        : '描述要做什么，或让我改哪个文件…';
      renderChat();
      renderFiles();
    }

    function renderChat() {
      chat.innerHTML = '';
      if ((!S.session || !S.session.hasVisibleMessages()) && !S.pending.length) {
        chat.innerHTML = WELCOME;
        chat.querySelectorAll('[data-say]').forEach((button) => {
          button.addEventListener('click', () => {
            input.value = button.getAttribute('data-say');
            send();
          });
        });
        return;
      }
      if (S.session) {
        for (const item of S.session.projectChat()) chat.appendChild(messageEl(item));
      }
      for (const message of S.pending) {
        const bubble = document.createElement('div');
        bubble.className = 'bubble user pending';
        bubble.textContent = message.text;
        chat.appendChild(bubble);
      }
      chat.scrollTop = chat.scrollHeight;
    }

    function messageEl(m) {
      if (m.role === 'tool') {
        const d = document.createElement('details');
        d.className = 'tool-card ' + (m.running ? 'running' : (m.ok ? 'ok' : 'bad'));
        if (m.running) d.open = true;
        const summary = document.createElement('summary');
        summary.innerHTML =
          '<span class="dot"></span><code>' + esc(m.name) + '</code>' +
          '<span class="tool-state">' + (m.running ? '执行中…' : (m.ok ? '完成' : '失败')) + '</span>';
        d.appendChild(summary);
        if (m.args) {
          const pre = document.createElement('pre');
          pre.textContent = m.args;
          d.appendChild(pre);
        }
        if (m.result) {
          const pre = document.createElement('pre');
          pre.className = 'result';
          pre.textContent = m.result;
          d.appendChild(pre);
        }
        return d;
      }
      const div = document.createElement('div');
      div.className = 'bubble ' + m.role;
      div.textContent = m.text;
      return div;
    }

    function renderFiles() {
      if (drawer.classList.contains('hidden')) return;
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

    async function openFile(path) {
      try {
        const read = normalizeRead(await ctx.workshop.read(S.draft.id, path));
        $('#viewerTitle').textContent = path;
        $('#viewerBody').textContent = read.content;
        viewer.classList.remove('hidden');
      } catch (e) {
        ctx.ui.toast('打开失败：' + (e && e.message ? e.message : e));
      }
    }

    function closeOverlays() {
      drawer.classList.add('hidden');
      backdrop.classList.add('hidden');
      viewer.classList.add('hidden');
    }

    function send() {
      const text = input.value.trim();
      if (!text || !S.session) return;
      input.value = '';
      const message = { text: text };
      const target = S.running ? 'next-step' : 'next-turn';
      S.pending.push(message);
      S.inbox.push(target, message);
      notify();
      if (!S.running) runAgent();
    }

    // ==================== 事件 ====================

    $('#btnSend').addEventListener('click', send);
    $('#btnStop').addEventListener('click', () => {
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
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        send();
      }
    });
    $('#draftSelect').addEventListener('change', async (e) => {
      if (S.running) {
        e.target.value = S.draft.id;
        return;
      }
      const next = S.drafts.find((d) => d.id === e.target.value) || S.drafts[0];
      if (!next || next.id === S.draft.id) return;
      try {
        await selectDraft(next);
      } catch (err) {
        ctx.ui.toast('切换失败：' + (err && err.message ? err.message : err));
      }
    });
    $('#btnNew').addEventListener('click', async () => {
      if (S.running) return;
      try {
        if (S.session) await S.session.flush();
        const draft = await ctx.workshop.create('未命名拓展');
        await refreshDraftList();
        S.drafts = [draft].concat(S.drafts.filter((d) => d.id !== draft.id));
        await selectDraft(draft);
        ctx.ui.toast('已新建草稿');
      } catch (e) {
        ctx.ui.toast('新建失败：' + (e && e.message ? e.message : e));
      }
    });
    $('#btnFiles').addEventListener('click', async () => {
      try {
        await refreshFiles();
      } catch (_) {}
      drawer.classList.remove('hidden');
      backdrop.classList.remove('hidden');
      renderFiles();
    });
    $('#btnCloseDrawer').addEventListener('click', closeOverlays);
    $('#btnCloseViewer').addEventListener('click', closeOverlays);
    backdrop.addEventListener('click', closeOverlays);
    $('#btnPreview').addEventListener('click', async () => {
      try {
        await ctx.workshop.preview(S.draft.id);
      } catch (e) {
        ctx.ui.toast('预览失败：' + (e && e.message ? e.message : e));
      }
    });
    $('#btnInstall').addEventListener('click', async () => {
      if (S.running) return;
      try {
        const result = await ctx.workshop.install(S.draft.id);
        if (result && result.denied) return;
        ctx.ui.toast('已安装，可在「拓展」页打开');
        await refreshDraftList();
        notify();
      } catch (e) {
        ctx.ui.toast('安装失败：' + (e && e.message ? e.message : e));
      }
    });

    ctx.effect(() => () => {
      S.alive = false;
      if (S.abort) S.abort.abort();
      S.inbox.clear();
      if (S.session) S.session.flush();
    }, 'workshop.cleanup');

    try {
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
