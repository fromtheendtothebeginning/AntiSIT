/// 新建草稿时写入的 main.js 模板：一个最小可运行的 Cordis 插件。
library;

String workshopMainTemplate(String name) => '''
// Cordis 拓展入口。保存后点右上角「预览」即可在 App 里运行。
export default {
  name: 'agent-extension',
  inject: ['ui'],
  apply(ctx) {
    ctx.ui.root.appendChild(AntiUI.page({
      title: '${_jsString(name)}',
      subtitle: '在这里写你的工具',
      children: [
        AntiUI.card({
          title: '开始吧',
          desc: '这是拓展工坊生成的 Cordis 拓展。',
          children: [
            AntiUI.button('点我', {
              block: true,
              variant: 'primary',
              onClick: () => ctx.ui.toast('你好'),
            }),
          ],
        }),
      ],
    }));
  },
};
''';

String _jsString(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n');

/// 新建草稿时写入的 style.css 模板（AntiUI 已提供基础样式）。
const String workshopCssTemplate = '''
/* AntiUI 已经提供基础样式；这里只写这个拓展自己的补充。 */
''';
