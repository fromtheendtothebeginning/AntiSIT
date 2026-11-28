import 'dart:io';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_background.dart';
import 'timetable_geometry.dart';

/// 课表页骨架：悬浮玻璃顶栏（学期标题 + 操作按钮）与 body 插槽。
Widget buildTimetableScaffold({
  required BuildContext context,
  required String title,
  required VoidCallback onTitleTap,
  required List<Widget> actions,
  required Widget body,
}) {
  return Scaffold(
    // 顶栏是悬浮玻璃条：内容从它底下穿过去，渐变模糊才有东西可糊
    extendBodyBehindAppBar: glassTopBarEnabled,
    appBar: glassAppBar(
      context,
      // 学期名靠左：它是这张表的标识；标题本身就是切换学期的入口。
      centerTitle: false,
      title: InkWell(
        onTap: onTitleTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_drop_down, size: 22),
            ],
          ),
        ),
      ),
      actions: actions,
    ),
    body: body,
  );
}

/// 课表页 body：背景图 + 顶部两块与分页的同一条竖向滚动 + 底部悬浮导航条。
Widget buildTimetableBody({
  required BuildContext context,
  required double topInset,
  required bool dayView,
  required VoidCallback onDayViewLayout,
  required Widget Function() todayCard,
  required Widget Function() examStrip,
  required Widget Function(double width) pagerBuilder,
  required Widget Function() navBar,
  Widget Function()? filterBanner,
}) {
  return GlassFadedBody(
    barHeight: topInset,
    child: ListenableBuilder(
      listenable: Listenable.merge([AppState.I, TtBackground.I]),
      builder: (context, _) {
        if (dayView) {
          // 日视图分页高度取当周各天内容的最高值（每天课数不同）——量完再设，故排一帧
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => onDayViewLayout(),
          );
        }
        return Stack(
          children: [
            // 自定义背景图：整页淡显铺底，垫在所有内容之下（没设置就不占层）
            if (TtBackground.I.path case final bgPath?)
              Positioned.fill(
                child: Opacity(
                  opacity: TtBackground.I.opacity.clamp(
                    TtBackground.minOpacity,
                    TtBackground.maxOpacity,
                  ),
                  child: Image.file(
                    File(bgPath),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            // 顶部两块与课表在同一条竖向滚动里，但在分页之外（切周 / 切天时不横移）；
            // 底部要让开玻璃浮层底栏，否则最后几节课与切换条会被压住。
            Positioned.fill(
              child: SingleChildScrollView(
                // 自绘滚动内容：顶部让出悬浮顶栏，初始状态内容不被顶栏压住
                padding: EdgeInsets.only(
                  top: topInset,
                  bottom: 90 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  children: [
                    if (!AppState.I.loggedIn)
                      buildGuestBanner(AppState.I.direct),
                    if (filterBanner != null) filterBanner(),
                    todayCard(),
                    examStrip(),
                    LayoutBuilder(
                      builder: (context, cons) => pagerBuilder(cons.maxWidth),
                    ),
                  ],
                ),
              ),
            ),
            // 底部悬浮导航条：周视图切周 / 日视图切天（压在玻璃底栏上方）
            Positioned(
              left: 0,
              right: 0,
              bottom: 12 + MediaQuery.paddingOf(context).bottom,
              child: navBar(),
            ),
          ],
        );
      },
    ),
  );
}

/// 未登录 / 未填凭据时的顶部提示条。
Widget buildGuestBanner(bool directMode) => Container(
  width: double.infinity,
  margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  decoration: BoxDecoration(
    color: SemColors.infoSoft,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: SemColors.info.withValues(alpha: 0.3)),
  ),
  child: Text(
    directMode
        ? '未填写校园凭据：手动编辑 / 调休等本地功能可正常使用，填写后可从教务导入课表与考试（需校园网）。'
        : '未登录：手动编辑 / 调休等本地功能可正常使用，登录后可从教务导入课表与考试。',
    style: TextStyle(fontSize: 12, color: SemColors.info, height: 1.5),
  ),
);

/// 周视图分页：只有课表格子（顶部两块在分页之外），高度固定（11 节网格）。
Widget buildWeekPager({
  required PageController controller,
  required int weekCount,
  required ValueChanged<int> onPageChanged,
  required Widget Function(int week) gridBuilder,
}) => SizedBox(
  height: weekPagerHeight,
  child: PageView.builder(
    controller: controller,
    itemCount: weekCount,
    onPageChanged: onPageChanged,
    itemBuilder: (context, i) => gridBuilder(i + 1),
  ),
);

/// 日视图分页：页高取当周 7 天内容的最大高度（矮的页留白，高的页不被裁）。
Widget buildDayPager({
  required PageController controller,
  required double width,
  required double height,
  required int weekCount,
  required int probeWeek,
  required List<GlobalKey> probeKeys,
  required ValueChanged<int> onPageChanged,
  required Widget Function(int week, int day) bodyBuilder,
}) => SizedBox(
  height: height,
  child: Stack(
    children: [
      PageView.builder(
        controller: controller,
        itemCount: weekCount * 7,
        onPageChanged: onPageChanged,
        // 内容按自然高度排（页高等量完再设）：先让 Column 拿到不限高，
        // 首帧内容比兜底高度高时也不会报 RenderFlex 溢出（会被分页裁掉一瞬）
        itemBuilder: (context, idx) => OverflowBox(
          alignment: Alignment.topLeft,
          minHeight: 0,
          maxHeight: double.infinity,
          child: bodyBuilder(idx ~/ 7 + 1, idx % 7),
        ),
      ),
      // 量高用的不可见副本：与分页同宽、高度不受分页约束，量出当周各天的自然高度
      for (var d = 0; d < 7; d++)
        Positioned(
          left: 0,
          top: 0,
          width: width,
          child: Offstage(
            child: KeyedSubtree(
              key: probeKeys[d],
              child: bodyBuilder(probeWeek, d),
            ),
          ),
        ),
    ],
  ),
);
