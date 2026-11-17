import 'dart:convert';

/// 网页消息通道名：评教页脚本只往这个通道发 JSON（内核负责注册，见 [WebViewHost]）。
const String kEvaluateChannel = 'antiSITEval';

/// 注入评教页的脚本：**扫描**页面上的评分项（单选组 / range 滑块 / jQuery UI 滑块 /
/// 分值下拉），把它们映射成 App 侧的一列滑块；并提供按项 / 统一改分的入口。
///
/// 与 App 的约定（消息都是 JSON 字符串，走的通道见 [kEvaluateChannel]）：
/// * `{t:'items', items:[{index,label,kind,value,min,max,step,values}]}` —— 扫到了什么；
/// * `{t:'none', login, counts:{radio,range,slider,select}}` —— 一个都没扫到（含计数，
///   用来区分「没登录」和「页面改版」）；
/// * `{t:'applied', values:{下标: 分值}}` —— 改完分之后的**真实**分值（离散项会被
///   页面就近取档，界面以回执为准）。
///
/// 页面上的改分方式按控件类型走：单选组点中分值最近的那个（`.click()` + change 事件）；
/// range 直接赋值再派发 input/change；jQuery UI 滑块优先调 API、拿不到就按比例模拟一次
/// 点击；下拉选分值最近的那一项。同源 iframe 里的控件也一起扫（正方部分页面套了框架）。
String evaluateInjectorJs({String channel = kEvaluateChannel}) =>
    _evaluateJs.replaceFirst('__ANTISIT_EVAL_CHANNEL__', "'$channel'");

/// 让页面按当前 DOM 重新扫一遍（注入之后调；页面自己跳转后由 App 重新注入再扫）。
const String kEvaluateScanCall = 'window.__antiSITEval && window.__antiSITEval.scan()';

/// 统一分数：一次改完所有评分项。
String evaluateApplyAllCall(double value) =>
    'window.__antiSITEval && window.__antiSITEval.applyAll(${jsonEncode(value)})';

/// 单项分数：只改第 [index] 项。
String evaluateApplyOneCall(int index, double value) =>
    'window.__antiSITEval && window.__antiSITEval.applyOne(${jsonEncode(index)}, ${jsonEncode(value)})';

const String _evaluateJs = r'''
(function () {
  if (window.__antiSITEval) return;
  var CH = __ANTISIT_EVAL_CHANNEL__;
  function post(o) {
    try { window[CH].postMessage(JSON.stringify(o)); } catch (e) {}
  }
  function num(x) {
    if (x === null || x === undefined) return null;
    var f = parseFloat(String(x).replace(/[^\d.\-]/g, ''));
    return isFinite(f) ? f : null;
  }
  function tidy(s) {
    s = String(s || '').replace(/\s+/g, ' ').trim();
    s = s.replace(/^[:：,，.、\-]+/, '').trim();
    return s.length > 42 ? s.slice(0, 42) + '…' : s;
  }
  function isField(el) {
    var t = (el.tagName || '').toUpperCase();
    return t === 'INPUT' || t === 'SELECT' || t === 'TEXTAREA' || t === 'BUTTON';
  }
  // 指标名：优先同一表格行里「不含控件」的那一格；否则往上找祖先里第一个纯文本块。
  function labelFor(el) {
    var tr = null;
    try { tr = el.closest ? el.closest('tr') : null; } catch (e) { tr = null; }
    if (tr) {
      var cells = tr.querySelectorAll('th, td');
      for (var i = 0; i < cells.length; i++) {
        if (cells[i].contains(el)) continue;
        var t0 = tidy(cells[i].innerText);
        if (t0) return t0;
      }
    }
    var node = el.parentElement;
    for (var d = 0; node && d < 6; d++) {
      var kids = node.children || [];
      for (var k = 0; k < kids.length; k++) {
        var c = kids[k];
        if (c === el || (c.contains && c.contains(el))) continue;
        if (isField(c)) continue;
        var txt = tidy(c.innerText || c.textContent);
        if (txt) return txt;
      }
      node = node.parentElement;
    }
    return '';
  }
  function scanDocs() {
    var out = [document];
    try {
      var frs = document.querySelectorAll('iframe');
      for (var i = 0; i < frs.length; i++) {
        try {
          var d = frs[i].contentDocument;
          if (d && d.body) out.push(d);
        } catch (e) {}
      }
    } catch (e) {}
    return out;
  }
  function looksLogin() {
    try { return !!document.querySelector('input[type="password"]'); } catch (e) { return false; }
  }
  function minGap(values) {
    var gap = 0;
    for (var i = 1; i < values.length; i++) {
      var d = Math.abs(values[i] - values[i - 1]);
      if (d > 1e-9 && (gap === 0 || d < gap)) gap = d;
    }
    return gap || 1;
  }

  var items = [];
  var counts = {radio: 0, range: 0, slider: 0, select: 0};

  // 单选组：同名下 >= 2 个数值选项才算评分项（「性别」这种非数值组自动跳过）。
  function collectRadio(doc) {
    var groups = {};
    var radios = doc.querySelectorAll('input[type="radio"]');
    for (var i = 0; i < radios.length; i++) {
      var r = radios[i];
      var name = r.name || '';
      if (!name) continue;
      (groups[name] = groups[name] || []).push(r);
    }
    Object.keys(groups).forEach(function (name) {
      var els = groups[name];
      if (els.length < 2) return;
      var values = [];
      var cur = null;
      for (var i = 0; i < els.length; i++) {
        var v = num(els[i].value);
        if (v === null || String(els[i].value).trim() === '') return;
        values.push(v);
        if (els[i].checked) cur = v;
      }
      values.sort(function (a, b) { return a - b; });
      if (values[values.length - 1] - values[0] < 1e-9) return;
      counts.radio++;
      items.push({
        kind: 'radio', els: els, el: null, value: cur,
        min: values[0], max: values[values.length - 1],
        step: minGap(values), values: values, label: labelFor(els[0])
      });
    });
  }

  function collectRange(doc) {
    var els = doc.querySelectorAll('input[type="range"]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var min = num(el.getAttribute('min'));
      var max = num(el.getAttribute('max'));
      if (min === null) min = 0;
      if (max === null) max = 100;
      if (max <= min) continue;
      var step = num(el.getAttribute('step'));
      counts.range++;
      items.push({
        kind: 'range', el: el, els: null, value: num(el.value) === null ? min : num(el.value),
        min: min, max: max, step: (step !== null && step > 0) ? step : 1,
        values: [], label: labelFor(el)
      });
    }
  }

  // 页面自带滑块（jQuery UI / role=slider）：分值藏在 aria-* 上。
  function collectSlider(doc) {
    var els = doc.querySelectorAll('.ui-slider, [role="slider"]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var min = num(el.getAttribute('aria-valuemin'));
      var max = num(el.getAttribute('aria-valuemax'));
      var cur = num(el.getAttribute('aria-valuenow'));
      if (min === null) min = 0;
      if (max === null) max = 100;
      if (max <= min) continue;
      counts.slider++;
      items.push({
        kind: 'slider', el: el, els: null, value: cur === null ? min : cur,
        min: min, max: max, step: 1, values: [], label: labelFor(el)
      });
    }
  }

  function collectSelect(doc) {
    var els = doc.querySelectorAll('select');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var values = [];
      for (var k = 0; k < el.options.length; k++) {
        var v = num(el.options[k].value);
        if (v !== null && String(el.options[k].value).trim() !== '') values.push(v);
      }
      values = values.filter(function (v, idx) { return values.indexOf(v) === idx; });
      if (values.length < 2) continue;
      values.sort(function (a, b) { return a - b; });
      counts.select++;
      var curVal = num(el.value);
      items.push({
        kind: 'select', el: el, els: null,
        value: curVal === null ? values[0] : curVal,
        min: values[0], max: values[values.length - 1],
        step: minGap(values), values: values, label: labelFor(el)
      });
    }
  }

  function nearestOf(els, v) {
    var best = null;
    var bestGap = Infinity;
    for (var i = 0; i < els.length; i++) {
      var x = num(els[i].value);
      if (x === null) continue;
      var gap = Math.abs(x - v);
      if (gap < bestGap) { bestGap = gap; best = els[i]; }
    }
    return best;
  }

  function setRadio(els, v) {
    var best = nearestOf(els, v);
    if (!best) return null;
    // 页面的 onchange / 校验多半挂在 click 上：先真的点一下，再补 change
    try { best.click(); } catch (e) {}
    best.checked = true;
    try { best.dispatchEvent(new Event('change', { bubbles: true })); } catch (e) {}
    return num(best.value);
  }

  function setRange(el, v) {
    el.value = String(v);
    try { el.dispatchEvent(new Event('input', { bubbles: true })); } catch (e) {}
    try { el.dispatchEvent(new Event('change', { bubbles: true })); } catch (e) {}
    return num(el.value);
  }

  function setSlider(el, v) {
    var jq = window.jQuery;
    if (jq && jq.fn && jq.fn.slider) {
      try {
        jq(el).slider('value', v);
        return num(el.getAttribute('aria-valuenow'));
      } catch (e) {}
    }
    try {
      var min = num(el.getAttribute('aria-valuemin'));
      var max = num(el.getAttribute('aria-valuemax'));
      if (min === null) min = 0;
      if (max === null) max = 100;
      var rect = el.getBoundingClientRect();
      var ratio = max > min ? (v - min) / (max - min) : 0;
      ratio = Math.max(0, Math.min(1, ratio));
      var x = rect.left + 8 + ratio * Math.max(1, rect.width - 16);
      var y = rect.top + rect.height / 2;
      ['mousedown', 'mousemove', 'mouseup'].forEach(function (t) {
        el.dispatchEvent(new MouseEvent(t, { bubbles: true, clientX: x, clientY: y }));
      });
      return num(el.getAttribute('aria-valuenow'));
    } catch (e) {
      return null;
    }
  }

  function setSelect(el, v) {
    var best = null;
    var bestGap = Infinity;
    for (var i = 0; i < el.options.length; i++) {
      var x = num(el.options[i].value);
      if (x === null) continue;
      var gap = Math.abs(x - v);
      if (gap < bestGap) { bestGap = gap; best = el.options[i]; }
    }
    if (!best) return null;
    el.value = best.value;
    try { el.dispatchEvent(new Event('change', { bubbles: true })); } catch (e) {}
    return num(el.value);
  }

  function apply(index, value) {
    var it = items[index];
    if (!it) return null;
    var v = parseFloat(value);
    if (!isFinite(v)) return it.value;
    var got = null;
    if (it.kind === 'radio') got = setRadio(it.els, v);
    else if (it.kind === 'range') got = setRange(it.el, v);
    else if (it.kind === 'slider') got = setSlider(it.el, v);
    else if (it.kind === 'select') got = setSelect(it.el, v);
    if (got === null) got = it.value;
    it.value = got;
    return got;
  }

  function payload() {
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var it = items[i];
      out.push({
        index: i, label: it.label, kind: it.kind, value: it.value,
        min: it.min, max: it.max, step: it.step, values: it.values || []
      });
    }
    return out;
  }

  window.__antiSITEval = {
    scan: function () {
      items = [];
      counts = {radio: 0, range: 0, slider: 0, select: 0};
      var docs = scanDocs();
      for (var i = 0; i < docs.length; i++) {
        try { collectRadio(docs[i]); } catch (e) {}
        try { collectRange(docs[i]); } catch (e) {}
        try { collectSlider(docs[i]); } catch (e) {}
        try { collectSelect(docs[i]); } catch (e) {}
      }
      var list = payload();
      if (!list.length) {
        post({ t: 'none', login: looksLogin(), counts: counts });
      } else {
        post({ t: 'items', login: looksLogin(), items: list, page: { title: document.title || '' } });
      }
      return list.length;
    },
    apply: apply,
    applyAll: function (value) {
      var out = {};
      for (var i = 0; i < items.length; i++) out[i] = apply(i, value);
      post({ t: 'applied', values: out });
      return items.length;
    },
    applyOne: function (index, value) {
      var got = apply(index, value);
      var out = {};
      out[index] = got;
      post({ t: 'applied', values: out });
      return got;
    }
  };
})();
''';
