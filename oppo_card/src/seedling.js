// 泛在卡片（UPK）的 JS 入口。
//
// 我们的卡片是「有宿主卡片」：课表数据由宿主 App（AntiSIT）通过
// SeedlingSupportSDK 的更新数据接口推过来，这里只处理生命周期与兜底数据，
// 保证宿主还没连上时卡片不是空白。

const FALLBACK = {
  slotText: '',
  dateText: '',
  courseName: '打开 AntiSIT 同步课表',
  place: '',
  timeRange: '',
  statusText: '',
  remainingText: '',
  actionText: '查看课表',
  voiceLabel: '打开 AntiSIT 同步课表',
  next1: '',
  next2: '',
  footerText: '',
};

export default {
  onCreate(cardInfo) {
    this.setData(cardInfo, FALLBACK);
  },

  onShow(cardInfo) {
    // 宿主每次打开/刷新会重新推数据；这里不重复覆盖
  },

  onDestroy(cardInfo) {
    // 卡片被移除：没有需要释放的资源
  },

  // 卡片按钮 / 整卡点击走 index.oml 的 uiEvent（deeplink），
  // 这个回调只作为备用：宿主也可以在这里收到 message 事件。
  openTimetable(cardInfo) {
    console.log('openTimetable tapped');
  },
};
