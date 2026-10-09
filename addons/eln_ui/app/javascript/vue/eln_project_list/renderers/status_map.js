// ELN 状态取值口径 —— 唯一真源。
//
// payload 的 `status` 是**原生推导的三态**（active / notstarted / done，
// 由 started_at / done_at 推得），spec SCN-PROJ-LIST 判据 5 明令不得用 PRD 五态
// （立项中/执行中/年度考核/结题中/已结题）冒充原生口径。
//
// ⚠ 为什么抽成模块：状态色点/标签在表格（status_renderer）与卡片（project_card）
// 两处都要用，各写一份就是第二真源，改一处漏一处 ⇒ 表格和卡片显示不一致。
export const ELN_STATUS = {
  active: { label: '进行中', color: '#3B99FD' },
  notstarted: { label: '未开始', color: '#98A2B3' },
  done: { label: '已完成', color: '#5EC66F' }
};

export const ELN_STATUS_FALLBACK = { label: '', color: '#98A2B3' };

export function elnStatus(key) {
  return ELN_STATUS[key] || ELN_STATUS_FALLBACK;
}
