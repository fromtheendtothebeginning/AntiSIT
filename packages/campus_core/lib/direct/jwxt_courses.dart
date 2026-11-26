part of 'jwxt.dart';

/// 正方 9.0 选课（zzxk）接口：轮次、课程、教学班、提交与已选课程。
extension JwxtCourseApi on JwxtClient {
  String get _courseReferer =>
      '$_jwglxt$zfCourseIndexPath?gnmkdm=$zfCourseGnmkdm&layout=default';

  Map<String, String> get _courseHeaders => {
        'Referer': _courseReferer,
        'X-Requested-With': 'XMLHttpRequest',
        'Origin': base,
      };

  String get _courseIndexUrl =>
      '$_jwglxt$zfCourseIndexPath?gnmkdm=$zfCourseGnmkdm&layout=default';

  /// 选课轮次：先读首页隐藏域与 queryCourse 类别，再逐类别请求展示页拿最新的
  /// xkkz_id / xkkz_xh；返回空表示当前没有开放选课。
  Future<List<CourseScope>> courseScopes() async {
    if (!loggedIn) throw ApiError('未登录教务系统');
    final resp = await _http.get(
      _courseIndexUrl,
      headers: {'Referer': '$_jwglxt/xtgl/index_initMenu.html'},
      redirect: false,
    );
    if (_deadSession(resp)) _sessionLost();
    if (isZfLoginPage(resp.text)) _sessionLost();

    final hidden = parseZfHiddenFields(resp.text);
    final categories = parseZfCourseCategories(resp.text, hidden);
    if (categories.isEmpty && (hidden['xkxnm'] ?? '').trim().isEmpty) {
      throw ApiError('未找到选课入口参数：当前可能未开放选课，或教务选课页面已改版');
    }
    if (categories.isEmpty) {
      return [
        CourseScope(id: 'zf-default', name: '选课', params: hidden),
      ];
    }

    final scopes = <CourseScope>[];
    for (var i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final body = buildZfDisplayParams(hidden, cat);
      final display = await _http.postForm(
        '$_jwglxt$zfCourseDisplayPath?gnmkdm=$zfCourseGnmkdm',
        body,
        headers: _courseHeaders,
        redirect: false,
      );
      if (_deadSession(display)) _sessionLost();
      if (isZfLoginPage(display.text)) _sessionLost();
      if (display.status >= 400) {
        throw ApiError('选课轮次「${cat.name.isEmpty ? cat.category : cat.name}」加载失败'
            '（HTTP ${display.status}）');
      }
      final params = cat.merge(hidden, parseZfHiddenFields(display.text));
      final name = cat.name.isNotEmpty
          ? cat.name
          : ((params['kklxmc'] ?? '').trim().isNotEmpty
              ? params['kklxmc']!.trim()
              : cat.category);
      scopes.add(CourseScope(
        id: 'zf-$i-${cat.category}',
        name: name.isEmpty ? '选课' : name,
        params: params,
      ));
    }
    return scopes;
  }

  /// 某轮次下的可选课程。[start] 是 0 基偏移，对应正方 kspage/jspage 的 1 基记录号。
  Future<List<CourseOffer>> courseOffers(
    CourseScope scope, {
    String keyword = '',
    int start = 0,
    int pageSize = 50,
  }) async {
    if (!loggedIn) throw ApiError('未登录教务系统');
    final body = buildZfCourseListParams(scope.params,
        keyword: keyword, start: start, pageSize: pageSize);
    final resp = await _http.postForm(
      '$_jwglxt$zfCourseListPath?gnmkdm=$zfCourseGnmkdm',
      body,
      headers: _courseHeaders,
      redirect: false,
    );
    if (_deadSession(resp)) _sessionLost();
    if (isZfLoginPage(resp.text)) _sessionLost();
    final j = _parse(resp);
    if (j == null) {
      throw ApiError('选课列表解析失败（教务返回的不是 JSON）：${loginPageSnippet(resp.text)}');
    }
    return parseZfCourseOffers(j, scopeId: scope.id, scopeParams: scope.params);
  }

  /// 某门课的教学班。
  Future<List<CourseSection>> courseSections(CourseOffer offer) async {
    if (!loggedIn) throw ApiError('未登录教务系统');
    final body = buildZfSectionParams(offer);
    final resp = await _http.postForm(
      '$_jwglxt$zfCourseSectionsPath?gnmkdm=$zfCourseGnmkdm',
      body,
      headers: _courseHeaders,
      redirect: false,
    );
    if (_deadSession(resp)) _sessionLost();
    if (isZfLoginPage(resp.text)) _sessionLost();
    final j = _parse(resp);
    if (j == null) {
      throw ApiError('教学班列表解析失败（教务返回的不是 JSON）：${loginPageSnippet(resp.text)}');
    }
    return parseZfCourseSections(j, offer);
  }

  /// 提交一次选课（写操作）；名额满等业务结果通过 [CourseSelectResult] 返回。
  Future<CourseSelectResult> selectCourse(
      CourseOffer offer, CourseSection section) async {
    if (!loggedIn) throw ApiError('未登录教务系统');
    final resp = await _http.postForm(
      '$_jwglxt$zfSelectCoursePath?gnmkdm=$zfCourseGnmkdm',
      buildZfSelectParams(offer, section),
      headers: _courseHeaders,
      redirect: false,
    );
    if (_deadSession(resp)) _sessionLost();
    final result = parseZfSelectResponse(resp.text, resp.status);
    if (result.status == CourseSelectStatus.sessionExpired) _sessionLost();
    return result;
  }

  /// 已选课程（用于确认抢课结果）。
  Future<List<SelectedCourse>> selectedCourses(CourseScope scope) async {
    if (!loggedIn) throw ApiError('未登录教务系统');
    final resp = await _http.postForm(
      '$_jwglxt$zfSelectedCoursesPath?gnmkdm=$zfCourseGnmkdm',
      buildZfSelectedParams(scope.params),
      headers: _courseHeaders,
      redirect: false,
    );
    if (_deadSession(resp)) _sessionLost();
    if (isZfLoginPage(resp.text)) _sessionLost();
    final j = _parse(resp);
    if (j == null) {
      throw ApiError('已选课程解析失败（教务返回的不是 JSON）：${loginPageSnippet(resp.text)}');
    }
    return parseZfSelectedCourses(j);
  }
}
