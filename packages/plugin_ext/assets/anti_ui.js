/* AntiUI：拓展页的统一组件。
 *
 * 和 anti_ui.css 配套，自动注入每个 Cordis 拓展页。所有组件都是普通 DOM，
 * 直接 append 到 ctx.ui.root 或 ctx.ui.push() 的 root 里即可：
 *
 *   const { files } = await ctx.files.pick({ accept: '.txt', multiple: true });
 *   ctx.ui.root.appendChild(AntiUI.page({
 *     title: '文件',
 *     children: [AntiUI.card({ title: files[0].name, desc: files[0].text })],
 *   }));
 *
 * 颜色 / 圆角 / 动效全部走 --antisit-*，不写死深浅色。
 */
(function () {
  if (window.AntiUI) return;

  var ICONS = {
    back: ['M15 18l-6-6 6-6'],
    chevron: ['M9 6l6 6-6 6'],
    close: ['M6 6l12 12', 'M18 6L6 18'],
    check: ['M5 12l5 5L20 7'],
    plus: ['M12 5v14', 'M5 12h14'],
    search: ['M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14z', 'M20 20l-4.2-4.2'],
    file: ['M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z', 'M14 3v5h5'],
    folder: ['M3 7a2 2 0 0 1 2-2h5l2 2h7a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'],
    download: ['M12 4v11', 'M8 11l4 4 4-4', 'M5 20h14'],
    upload: ['M12 20V9', 'M8 13l4-4 4 4', 'M5 4h14'],
    trash: ['M4 7h16', 'M9 7V5h6v2', 'M7 7l1 13h8l1-13'],
    info: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M12 11v5', 'M12 8h.01'],
    refresh: ['M20 11a8 8 0 1 0-2.3 6.3', 'M20 5v6h-6'],
    copy: ['M9 9h10v12H9z', 'M5 15V3h10'],
    send: ['M4 12l16-8-6 16-2-6z'],
    sparkles: ['M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z', 'M19 16l.6 1.8L21 18l-1.4.6L19 20l-.6-1.4L17 18l1.4-.6z'],
    link: ['M10 14a4 4 0 0 0 5.7 0l2.6-2.6a4 4 0 0 0-5.7-5.7L11 7.3', 'M14 10a4 4 0 0 0-5.7 0l-2.6 2.6a4 4 0 0 0 5.7 5.7l1.6-1.6'],
    clock: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M12 7v5l3 2'],
    more: ['M5 12h.01', 'M12 12h.01', 'M19 12h.01'],
  };

  var SVG_NS = 'http://www.w3.org/2000/svg';

  function icon(name, size) {
    var svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('width', size || 18);
    svg.setAttribute('height', size || 18);
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '1.8');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    svg.setAttribute('aria-hidden', 'true');
    var paths = ICONS[name] || ICONS.info;
    for (var i = 0; i < paths.length; i++) {
      var path = document.createElementNS(SVG_NS, 'path');
      path.setAttribute('d', paths[i]);
      svg.appendChild(path);
    }
    return svg;
  }

  function append(node, child) {
    if (child == null || child === false) return;
    if (Array.isArray(child)) {
      for (var i = 0; i < child.length; i++) append(node, child[i]);
      return;
    }
    node.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
  }

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    if (attrs) {
      for (var key in attrs) {
        if (!Object.prototype.hasOwnProperty.call(attrs, key)) continue;
        var value = attrs[key];
        if (value == null || value === false) continue;
        if (key === 'class') node.className = value;
        else if (key === 'text') node.textContent = value;
        else if (key === 'html') node.innerHTML = value;
        else if (key === 'style' && typeof value === 'object') {
          for (var s in value) node.style[s] = value[s];
        } else if (key.indexOf('on') === 0 && typeof value === 'function') {
          node.addEventListener(key.slice(2).toLowerCase(), value);
        } else if (value === true) {
          node.setAttribute(key, '');
        } else {
          node.setAttribute(key, String(value));
        }
      }
    }
    append(node, children);
    return node;
  }

  function cls(base, extra) {
    return extra ? base + ' ' + extra : base;
  }

  function button(label, opts) {
    if (label && typeof label === 'object') {
      opts = label;
      label = opts.label || '';
    }
    opts = opts || {};
    var variant = opts.variant ? ' au-btn--' + opts.variant : '';
    var node = el('button', {
      type: opts.type || 'button',
      class: cls('au-btn' + variant, (opts.block ? 'au-btn--block ' : '') + (opts.class || '')),
      disabled: opts.disabled,
      'aria-label': opts.ariaLabel,
      onClick: opts.onClick,
    }, [
      opts.icon ? icon(opts.icon, opts.iconSize || 17) : null,
      label ? el('span', { text: label }) : null,
    ]);
    return node;
  }

  function iconButton(name, opts) {
    opts = opts || {};
    return el('button', {
      type: 'button',
      class: cls('au-icon-btn', opts.class || ''),
      'aria-label': opts.label || name,
      onClick: opts.onClick,
    }, icon(name, opts.size || 20));
  }

  function card(opts) {
    opts = opts || {};
    var hasBody = opts.children != null && opts.children !== '' &&
      !(Array.isArray(opts.children) && opts.children.length === 0);
    var body = null;
    if (hasBody) {
      body = el('div', { class: 'au-card-body' });
      append(body, opts.children);
    }
    var node = el('div', {
      class: cls('au-card' + (opts.flat ? ' au-card--flat' : '') + (opts.tight ? ' au-card--tight' : ''),
        (opts.onClick ? 'au-card--tap ' : '') + (opts.class || '')),
      onClick: opts.onClick,
      role: opts.onClick ? 'button' : null,
      tabindex: opts.onClick ? '0' : null,
    }, [
      opts.title ? el('div', { class: 'au-card-title', text: opts.title }) : null,
      opts.desc ? el('div', { class: 'au-card-desc', text: opts.desc }) : null,
      body,
      opts.actions ? el('div', { class: 'au-card-actions' }, opts.actions) : null,
    ]);
    if (opts.onClick) {
      node.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          opts.onClick(e);
        }
      });
    }
    return node;
  }

  function row(opts) {
    opts = opts || {};
    var side = opts.side;
    if (opts.chevron) {
      side = el('span', { class: 'au-row-side' }, [
        side,
        el('span', { class: 'au-row-chevron' }, icon('chevron', 16)),
      ]);
    } else if (side != null) {
      side = el('span', { class: 'au-row-side' }, side);
    }
    return el('div', {
      class: cls('au-row' + (opts.onClick ? ' au-row--tap' : ''), opts.class || ''),
      role: opts.onClick ? 'button' : null,
      tabindex: opts.onClick ? '0' : null,
      onClick: opts.onClick,
    }, [
      opts.icon ? el('span', { class: 'au-row-icon' }, icon(opts.icon, 17)) : null,
      el('div', { class: 'au-row-main' }, [
        el('div', {
          class: 'au-row-title',
          text: opts.title || '',
          style: opts.danger ? { color: 'var(--au-danger)' } : null,
        }),
        opts.desc ? el('div', { class: 'au-row-desc', text: opts.desc }) : null,
      ]),
      side,
      opts.trailing || null,
    ]);
  }

  function list(items) {
    var node = el('div', { class: 'au-list' });
    (items || []).forEach(function (item) {
      node.appendChild(item && item.nodeType ? item : row(item));
    });
    return node;
  }

  function field(opts) {
    opts = opts || {};
    return el('div', { class: cls('au-field', opts.class || '') }, [
      opts.label ? el('div', { class: 'au-label', text: opts.label }) : null,
      opts.control || opts.children,
      opts.hint ? el('div', { class: 'au-hint', text: opts.hint }) : null,
    ]);
  }

  function input(opts) {
    opts = opts || {};
    var control = el('input', {
      class: 'au-input',
      type: opts.type || 'text',
      value: opts.value == null ? '' : opts.value,
      placeholder: opts.placeholder || '',
      inputmode: opts.inputmode,
      autocomplete: opts.autocomplete,
      maxlength: opts.maxlength,
      disabled: opts.disabled,
      onInput: opts.onInput,
      onChange: opts.onChange,
    });
    var node = field({ label: opts.label, hint: opts.hint, control: control });
    node.input = control;
    return node;
  }

  function textarea(opts) {
    opts = opts || {};
    var control = el('textarea', {
      class: 'au-textarea',
      placeholder: opts.placeholder || '',
      rows: opts.rows || 4,
      maxlength: opts.maxlength,
      onInput: opts.onInput,
    });
    if (opts.value != null) control.value = opts.value;
    var node = field({ label: opts.label, hint: opts.hint, control: control });
    node.textarea = control;
    return node;
  }

  function switchRow(opts) {
    opts = opts || {};
    var track = el('span', { class: 'au-switch-track' }, el('span', { class: 'au-switch-thumb' }));
    var inputEl = el('input', {
      type: 'checkbox',
      checked: opts.checked === true,
      disabled: opts.disabled,
      onChange: function () {
        if (opts.onChange) opts.onChange(inputEl.checked);
      },
    });
    return row({
      title: opts.title,
      desc: opts.desc,
      icon: opts.icon,
      danger: opts.danger,
      trailing: el('label', { class: 'au-switch' }, [inputEl, track]),
      class: opts.class,
    });
  }

  function segmented(opts) {
    opts = opts || {};
    var items = opts.items || [];
    var root = el('div', { class: cls('au-seg', opts.class || '') });
    var thumb = el('span', { class: 'au-seg-thumb' });
    root.appendChild(thumb);
    var buttons = [];
    var index = typeof opts.index === 'number' ? opts.index : 0;
    if (opts.value != null) {
      for (var i = 0; i < items.length; i++) {
        var item = items[i];
        var value = item && typeof item === 'object' ? item.value : item;
        if (value === opts.value) { index = i; break; }
      }
    }
    if (items.length) index = Math.max(0, Math.min(items.length - 1, index));

    function paint() {
      var active = buttons[index];
      if (!active) return;
      var rootRect = root.getBoundingClientRect();
      var btnRect = active.getBoundingClientRect();
      if (!btnRect.width) return;
      var border = parseFloat(getComputedStyle(root).borderLeftWidth) || 0;
      thumb.style.width = btnRect.width + 'px';
      thumb.style.transform =
        'translateX(' + Math.max(0, btnRect.left - rootRect.left - border) + 'px)';
    }

    function set(next, silent) {
      index = next;
      buttons.forEach(function (b, j) { b.classList.toggle('active', j === next); });
      paint();
      if (!silent && opts.onChange) {
        var item = items[next];
        opts.onChange(next, item && typeof item === 'object' ? item.value : item);
      }
    }

    items.forEach(function (item, i) {
      var label = item && typeof item === 'object' ? item.label : item;
      var b = el('button', {
        type: 'button',
        class: i === index ? 'active' : '',
        text: label,
        onClick: function () { set(i); },
      });
      buttons.push(b);
      root.appendChild(b);
    });

    root.set = set;
    root.getValue = function () { return index; };
    requestAnimationFrame(paint);
    if (window.ResizeObserver) {
      try { new ResizeObserver(paint).observe(root); } catch (_) {}
    }
    return root;
  }

  function chips(items, opts) {
    opts = opts || {};
    var root = el('div', { class: cls('au-chips', opts.class || '') });
    var selected = opts.value;
    var nodes = [];
    (items || []).forEach(function (item, i) {
      var label = item && typeof item === 'object' ? item.label : item;
      var value = item && typeof item === 'object' ? item.value : item;
      var chip = el('button', {
        type: 'button',
        class: 'au-chip' + (value === selected ? ' active' : ''),
        text: label,
        onClick: function () {
          if (opts.onChange) opts.onChange(value, i);
          if (opts.single !== false) {
            selected = value;
            nodes.forEach(function (n, j) {
              n.classList.toggle('active', j === i);
            });
          } else {
            chip.classList.toggle('active');
          }
        },
      });
      nodes.push(chip);
      root.appendChild(chip);
    });
    return root;
  }

  function title(text, sub) {
    return el('div', null, [
      el('div', { class: 'au-title', text: text || '' }),
      sub ? el('div', { class: 'au-subtitle', text: sub }) : null,
    ]);
  }

  function topbar(opts) {
    opts = opts || {};
    return el('div', { class: 'au-topbar' }, [
      opts.onBack ? iconButton('back', { label: '返回', onClick: opts.onBack }) : null,
      el('div', { class: 'au-topbar-main' }, [
        el('div', { class: 'au-topbar-title', text: opts.title || '' }),
        opts.subtitle ? el('div', { class: 'au-topbar-sub', text: opts.subtitle }) : null,
      ]),
      opts.actions,
    ]);
  }

  function page(opts) {
    opts = opts || {};
    var body = el('div', { class: 'au-stack' });
    if (opts.children) append(body, opts.children);
    return el('div', {
      class: cls('au-page' + (opts.flush ? ' au-page--flush' : '') + (opts.topbar ? ' au-page--bar' : ''),
        opts.class || ''),
    }, [
      opts.topbar || null,
      opts.title || opts.subtitle
        ? el('div', { class: 'au-page-head' }, title(opts.title, opts.subtitle))
        : null,
      body,
    ]);
  }

  function empty(opts) {
    opts = opts || {};
    return el('div', { class: cls('au-empty', opts.class || '') }, [
      el('div', { class: 'au-empty-icon' }, icon(opts.icon || 'file', 30)),
      el('div', { class: 'au-empty-title', text: opts.title || '这里还没有内容' }),
      opts.desc ? el('div', { class: 'au-empty-desc', text: opts.desc }) : null,
      opts.action ? el('div', { class: 'au-empty-action' }, opts.action) : null,
    ]);
  }

  function spinner() {
    return el('span', { class: 'au-spinner', 'aria-label': '加载中' });
  }

  function loading(text) {
    return el('span', { class: 'au-loading' }, [spinner(), text || '加载中']);
  }

  function progress(value) {
    var bar = el('i');
    var root = el('div', { class: 'au-progress', role: 'progressbar' }, bar);
    root.set = function (next) {
      var v = Math.max(0, Math.min(1, Number(next) || 0));
      bar.style.width = (v * 100).toFixed(1) + '%';
      root.setAttribute('aria-valuenow', String(Math.round(v * 100)));
    };
    if (value != null) root.set(value);
    return root;
  }

  function mountBackdrop(center) {
    var backdrop = el('div', { class: 'au-backdrop' + (center ? ' au-backdrop--center' : '') });
    document.body.appendChild(backdrop);
    requestAnimationFrame(function () { backdrop.classList.add('show'); });
    return backdrop;
  }

  function dismiss(backdrop, callback) {
    backdrop.classList.remove('show');
    setTimeout(function () {
      if (backdrop.parentNode) backdrop.parentNode.removeChild(backdrop);
      if (callback) callback();
    }, 220);
  }

  function sheet(opts) {
    opts = opts || {};
    var panel = el('div', { class: 'au-sheet' });
    var backdrop = mountBackdrop(false);
    backdrop.appendChild(panel);
    panel.appendChild(el('div', { class: 'au-grabber' }));
    if (opts.title) panel.appendChild(el('div', { class: 'au-dialog-title', text: opts.title }));
    if (opts.desc) panel.appendChild(el('div', { class: 'au-dialog-text', text: opts.desc }));
    if (opts.content) {
      panel.appendChild(el('div', { class: 'au-sheet-body' },
        typeof opts.content === 'function' ? opts.content() : opts.content));
    }
    if (opts.actions && opts.actions.length) {
      panel.appendChild(el('div', { class: 'au-dialog-actions' }, opts.actions));
    }
    var closed = false;
    function close() {
      if (closed) return;
      closed = true;
      dismiss(backdrop, opts.onClose);
    }
    backdrop.addEventListener('click', function (e) {
      if (e.target === backdrop) close();
    });
    return { root: panel, el: backdrop, close: close };
  }

  function dialog(opts) {
    opts = opts || {};
    var panel = el('div', { class: 'au-dialog' });
    var backdrop = mountBackdrop(true);
    backdrop.appendChild(panel);
    if (opts.title) panel.appendChild(el('div', { class: 'au-dialog-title', text: opts.title }));
    if (opts.text) panel.appendChild(el('div', { class: 'au-dialog-text', text: opts.text }));
    if (opts.content) append(panel, typeof opts.content === 'function' ? opts.content() : opts.content);
    var closed = false;
    function close(value) {
      if (closed) return;
      closed = true;
      dismiss(backdrop, function () {
        if (opts.onClose) opts.onClose(value);
      });
    }
    if (opts.actions) {
      panel.appendChild(el('div', { class: 'au-dialog-actions' }, opts.actions));
    }
    backdrop.addEventListener('click', function (e) {
      if (e.target === backdrop) close(opts.cancelValue);
    });
    return { root: panel, el: backdrop, close: close };
  }

  function confirm(opts) {
    opts = opts || {};
    return new Promise(function (resolve) {
      var done = false;
      function finish(value) {
        if (done) return;
        done = true;
        resolve(value);
      }
      var d = dialog({
        title: opts.title || '确认',
        text: opts.text || '',
        content: opts.content,
        onClose: function () { finish(false); },
        actions: [
          button(opts.cancelText || '取消', {
            class: 'au-btn--ghost',
            onClick: function () { d.close(); finish(false); },
          }),
          button(opts.confirmText || '确定', {
            variant: opts.danger ? 'danger' : 'primary',
            onClick: function () { d.close(); finish(true); },
          }),
        ],
      });
    });
  }

  function actions(opts) {
    opts = opts || {};
    return new Promise(function (resolve) {
      var body = el('div', { class: 'au-stack au-stack--tight' });
      var stack = sheet({
        title: opts.title,
        desc: opts.desc,
        content: body,
        onClose: function () { resolve(null); },
      });
      (opts.items || []).forEach(function (item) {
        body.appendChild(row({
          title: item.label,
          desc: item.desc,
          danger: item.danger,
          onClick: function () {
            stack.close();
            resolve(item.value !== undefined ? item.value : item.label);
          },
        }));
      });
      if (!opts.items || !opts.items.length) {
        body.appendChild(empty({ title: '没有可选项' }));
      }
    });
  }

  var fallbackTimer = null;

  function toast(text) {
    var value = String(text == null ? '' : text).trim();
    if (!value) return;
    try {
      if (window.antiSIT && window.antiSIT.call) {
        window.antiSIT.post('toast', { text: value });
        return;
      }
    } catch (_) {}
    var node = el('div', {
      style: {
        position: 'fixed',
        left: '50%',
        bottom: 'calc(28px + env(safe-area-inset-bottom))',
        transform: 'translate(-50%, 8px)',
        maxWidth: '82vw',
        padding: '9px 14px',
        borderRadius: '12px',
        background: 'var(--antisit-menu-bg, rgba(24,24,28,.9))',
        color: 'var(--antisit-fg, #fff)',
        border: '1px solid var(--antisit-border, transparent)',
        boxShadow: '0 8px 24px var(--antisit-shadow, rgba(0,0,0,.2))',
        fontSize: '12.5px',
        lineHeight: '1.5',
        zIndex: '1000',
        opacity: '0',
        transition: 'opacity .18s ease, transform .18s ease',
        pointerEvents: 'none',
      },
      text: value,
    });
    document.body.appendChild(node);
    requestAnimationFrame(function () {
      node.style.opacity = '1';
      node.style.transform = 'translate(-50%, 0)';
    });
    clearTimeout(fallbackTimer);
    fallbackTimer = setTimeout(function () {
      node.style.opacity = '0';
      node.style.transform = 'translate(-50%, 6px)';
      setTimeout(function () { if (node.parentNode) node.parentNode.removeChild(node); }, 220);
    }, 1800);
  }

  function formatBytes(bytes) {
    var n = Number(bytes) || 0;
    if (n >= 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + ' MB';
    if (n >= 1024) return Math.round(n / 1024) + ' KB';
    return n + ' B';
  }

  function copy(text) {
    var value = String(text == null ? '' : text);
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(value).then(function () { return true; }, function () {
        return legacyCopy(value);
      });
    }
    return Promise.resolve(legacyCopy(value));
  }

  function legacyCopy(value) {
    try {
      var area = el('textarea', {
        style: { position: 'fixed', left: '-9999px', top: '0', opacity: '0' },
      });
      area.value = value;
      document.body.appendChild(area);
      area.select();
      var ok = document.execCommand && document.execCommand('copy');
      document.body.removeChild(area);
      return !!ok;
    } catch (_) {
      return false;
    }
  }

  window.AntiUI = {
    version: '1.0.0',
    icons: Object.keys(ICONS),
    icon: icon,
    el: el,
    append: append,
    button: button,
    iconButton: iconButton,
    card: card,
    row: row,
    list: list,
    field: field,
    input: input,
    textarea: textarea,
    switchRow: switchRow,
    segmented: segmented,
    chips: chips,
    title: title,
    topbar: topbar,
    page: page,
    empty: empty,
    spinner: spinner,
    loading: loading,
    progress: progress,
    sheet: sheet,
    dialog: dialog,
    confirm: confirm,
    actions: actions,
    toast: toast,
    copy: copy,
    formatBytes: formatBytes,
  };
})();
