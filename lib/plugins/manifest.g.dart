// GENERATED FILE —— 不要手改。
//
// 插件集合 = pubspec.yaml 里以 plugin_ 开头的依赖；改完依赖后运行：
//   dart run tool/gen_plugins.dart
//
// 每个 if 都是编译期常量判断：--dart-define=EXCLUDE_XXX=true 构建时该分支
// 不可达，插件包代码被 AOT 摇树丢弃（真正减小包体）。
//
// ignore_for_file: unused_import, prefer_single_quotes

import 'package:campus_core/campus_core.dart';

import 'package:plugin_feedback/plugin_feedback.dart' as plugin_feedback;
import 'package:plugin_electricity/plugin_electricity.dart' as plugin_electricity;
import 'package:plugin_activities/plugin_activities.dart' as plugin_activities;
import 'package:plugin_score/plugin_score.dart' as plugin_score;
import 'package:plugin_exams/plugin_exams.dart' as plugin_exams;
import 'package:plugin_grades/plugin_grades.dart' as plugin_grades;
import 'package:plugin_timetable/plugin_timetable.dart' as plugin_timetable;
import 'package:plugin_webview/plugin_webview.dart' as plugin_webview;
import 'package:plugin_ext/plugin_ext.dart' as plugin_ext;
import 'package:plugin_ecard/plugin_ecard.dart' as plugin_ecard;
import 'package:plugin_tools/plugin_tools.dart' as plugin_tools;
import 'package:plugin_ai/plugin_ai.dart' as plugin_ai;
import 'package:plugin_appearance/plugin_appearance.dart' as plugin_appearance;
import 'package:plugin_risk/plugin_risk.dart' as plugin_risk;
import 'package:plugin_ai_deepseek/plugin_ai_deepseek.dart' as plugin_ai_deepseek;
import 'package:plugin_ai_opencode_go/plugin_ai_opencode_go.dart' as plugin_ai_opencode_go;
import 'package:plugin_ai_kimi/plugin_ai_kimi.dart' as plugin_ai_kimi;
import 'package:plugin_ai_glm/plugin_ai_glm.dart' as plugin_ai_glm;
import 'package:plugin_ai_qwen/plugin_ai_qwen.dart' as plugin_ai_qwen;
import 'package:plugin_ai_gpt/plugin_ai_gpt.dart' as plugin_ai_gpt;
import 'package:plugin_ai_gemini/plugin_ai_gemini.dart' as plugin_ai_gemini;
import 'package:plugin_ai_mimo/plugin_ai_mimo.dart' as plugin_ai_mimo;
import 'package:plugin_ai_minimax/plugin_ai_minimax.dart' as plugin_ai_minimax;
import 'package:plugin_reminder/plugin_reminder.dart' as plugin_reminder;
import 'package:plugin_theme_glass/plugin_theme_glass.dart' as plugin_theme_glass;
import 'package:plugin_theme_ink/plugin_theme_ink.dart' as plugin_theme_ink;
import 'package:plugin_theme_bamboo/plugin_theme_bamboo.dart' as plugin_theme_bamboo;

/// 本次构建包含的插件包（顺序 = pubspec.yaml 里的书写顺序）。
List<PluginBundle> get pluginBundles => [
      if (!const bool.fromEnvironment('EXCLUDE_FEEDBACK')) plugin_feedback.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_ELECTRICITY')) plugin_electricity.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_ACTIVITIES')) plugin_activities.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_SCORE')) plugin_score.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_EXAMS')) plugin_exams.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_GRADES')) plugin_grades.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_TIMETABLE')) plugin_timetable.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_WEBVIEW')) plugin_webview.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_EXT')) plugin_ext.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_ECARD')) plugin_ecard.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_TOOLS')) plugin_tools.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_AI')) plugin_ai.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_APPEARANCE')) plugin_appearance.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_RISK')) plugin_risk.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_AI_DEEPSEEK')) plugin_ai_deepseek.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_AI_OPENCODE_GO')) plugin_ai_opencode_go.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_AI_KIMI')) plugin_ai_kimi.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_AI_GLM')) plugin_ai_glm.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_AI_QWEN')) plugin_ai_qwen.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_AI_GPT')) plugin_ai_gpt.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_AI_GEMINI')) plugin_ai_gemini.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_AI_MIMO')) plugin_ai_mimo.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_AI_MINIMAX')) plugin_ai_minimax.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_REMINDER')) plugin_reminder.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_THEME_GLASS')) plugin_theme_glass.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_THEME_INK')) plugin_theme_ink.pluginBundle,
      if (!const bool.fromEnvironment('EXCLUDE_THEME_BAMBOO')) plugin_theme_bamboo.pluginBundle,
    ];
