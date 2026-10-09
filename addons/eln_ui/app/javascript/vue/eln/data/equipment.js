// ============================================================
// 设备预定页演示数据 + 日历算法（对齐 Ardot 画布 设备预定页 V1.8）
// 三态（日/周/月）共用一份 bookings 平面表，按 deviceId + date 过滤。
// 注意：TODAY 固定为 2026-09-29（画布演示锚点），保证「今天」高亮与当前时间线
//       与设计稿一致；接入真实接口后改为 new Date() 即可。
// ============================================================

// 演示锚点：2026-09-29（周二）
export const TODAY = new Date(2026, 8, 29)

// 周视图 / 日视图时间窗（画布默认 08:00–20:00，40px/h）
export const HOUR_START = 8
export const HOUR_END = 20
export const PX_PER_HOUR = 40

// ---------- 设备列表（左栏 300px）----------
// status: idle 空闲 / in-use 使用中 / maintenance 维护中
// 逐项取自画布 70:36 / 70:44 / 70:52 / 70:60 / 70:68（名称 / 型号行 / 状态 chip / 图标字 70:38,46,54,62,70）
export const devices = [
  { id: 'UTM-500', name: '电子万能试验机', code: 'UTM-500', spec: '力值 500 kN', icon: '拉', owner: '王强', status: 'idle' },
  { id: 'MDR-2000', name: '无转子硫化仪', code: 'MDR-2000', spec: '180°C', icon: '硫', owner: '王强', status: 'in-use' },
  { id: 'DSC-100', name: '差示扫描量热仪', code: 'DSC 3+', spec: '-90~550°C', icon: '热', owner: '王强', status: 'idle' },
  { id: 'GE-808', name: '老化试验箱', code: 'GE-808', spec: '150°C 蒸汽', icon: '老', owner: '王强', status: 'maintenance' },
  { id: 'GDH-050W', name: '高低温恒温槽', code: 'GDH-050W', spec: '-20~100°C', icon: '槽', owner: '王强', status: 'idle' }
]

export const deviceStatusText = {
  idle: '空闲',
  'in-use': '使用中',
  maintenance: '维护中'
}

// 状态 chip 配色（左栏 + 当前设备条共用）
// 画布实测：空闲 70:42 #E7F7E9/#15803D · 使用中 70:50 #FFF7ED/#B45309 · 维护中 70:66 #F4F4F5/#71717A
// chip 内**无圆点**（70:42 子节点只有文案），故不再输出 dot
export const deviceStatusStyle = {
  idle: { bg: '#E7F7E9', fg: '#15803D' },
  'in-use': { bg: '#FFF7ED', fg: '#B45309' },
  maintenance: { bg: '#F4F4F5', fg: '#71717A' }
}

// 预约类型配色（图例 + 事件块共用）
// 画布实测：事件块 70:114 已占用 #DBE4F2/#3F3F46 · 70:117 我的预定 #2563EB/#FFF
//           图例 70:150 / 70:156 / 72:6 色块同值
export const bookingTypeStyle = {
  occupied: { bg: '#DBE4F2', fg: '#3F3F46', label: '已占用' },
  mine: { bg: '#2563EB', fg: '#FFFFFF', label: '我的预定' },
  maintenance: { bg: '#E4E4E7', fg: '#3F3F46', label: '维护中' }
}

// ---------- 预约事件平面表 ----------
// type: mine 我的预定（主色）/ occupied 已占用（浅蓝）/ maintenance 维护中（灰）
// ★ 逐块取自画布 V1.22：
//   周视图 70:203 —— 9/28「10:00-12:00 李娜 · EX3」/ 9/29「09:00-11:00 王强 · EX1 拉伸」
//                     +「14:00-16:00 我的预定 · EX2」/ 9/30「13:00-15:00 张伟 · EX4」
//                     / 10/1「09:00-17:00 维护 · 国庆检定」
//   日视图 70:12 —— 与周视图 9/29 同两块（文案一致）
//   月视图 70:418 —— 9/2「李娜 · EX3」/ 9/10「张伟 · EX4」/ 9/15「王强 · EX1」
//                     / 9/22「维护 · 检定」/ 9/29 两格 / 10/1「国庆检定」
//   ⚠ 月视图仅给出「负责人 · 实验号」标签，未给时段 → 该 4 条的 start/end 为演示补全，已在注释标注。
export const bookings = [
  // —— 周 / 日视图（2026-09-28 ~ 10-04）——
  { id: 'B01', deviceId: 'UTM-500', title: '粘接试样制备', owner: '李娜', type: 'occupied', date: '2026-09-28', start: '10:00', end: '12:00', relatedExp: 'EX3' },
  { id: 'B02', deviceId: 'UTM-500', title: '拉伸强度测试', short: '拉伸', owner: '王强', type: 'occupied', date: '2026-09-29', start: '09:00', end: '11:00', relatedExp: 'EX1' },
  { id: 'B03', deviceId: 'UTM-500', title: 'EX2 拉伸复测', owner: '王强', type: 'mine', date: '2026-09-29', start: '14:00', end: '16:00', relatedExp: 'EX2', approver: '王强' },
  { id: 'B04', deviceId: 'UTM-500', title: 'PP 配方验证', owner: '张伟', type: 'occupied', date: '2026-09-30', start: '13:00', end: '15:00', relatedExp: 'EX4' },
  { id: 'B05', deviceId: 'UTM-500', title: '国庆检定', owner: '维护', type: 'maintenance', date: '2026-10-01', start: '09:00', end: '17:00' },

  // —— 月视图其他日期（时段为演示补全，标签取自画布）——
  { id: 'B06', deviceId: 'UTM-500', title: '粘接试样制备', owner: '李娜', type: 'occupied', date: '2026-09-02', start: '09:30', end: '11:00', relatedExp: 'EX3' },
  { id: 'B07', deviceId: 'UTM-500', title: '混料均匀性验证', owner: '张伟', type: 'occupied', date: '2026-09-10', start: '14:00', end: '15:30', relatedExp: 'EX4' },
  { id: 'B08', deviceId: 'UTM-500', title: '高温老化试样测试', owner: '王强', type: 'occupied', date: '2026-09-15', start: '10:00', end: '11:30', relatedExp: 'EX1' },
  { id: 'B09', deviceId: 'UTM-500', title: '检定', owner: '维护', type: 'maintenance', date: '2026-09-22', start: '08:30', end: '10:00' },

  // —— 其他设备占位（画布仅演示 UTM-500；切换设备后可见，避免空日历）——
  { id: 'C01', deviceId: 'DSC-100', title: 'Tg 测试', owner: '刘研究员', type: 'mine', date: '2026-09-29', start: '10:00', end: '12:00', relatedExp: 'EX1', approver: '王强' },
  { id: 'C02', deviceId: 'DSC-100', title: '结晶度表征', owner: '张伟', type: 'occupied', date: '2026-09-30', start: '14:00', end: '16:00', relatedExp: 'EX4' },
  { id: 'C03', deviceId: 'MDR-2000', title: '门尼粘度连续监测', owner: '王强', type: 'mine', date: '2026-09-29', start: '08:30', end: '17:30', relatedExp: 'EX1', approver: '王强' },
  { id: 'C04', deviceId: 'GE-808', title: '150℃ 蒸汽老化', owner: '计量室', type: 'maintenance', date: '2026-09-29', start: '00:00', end: '23:59' }
]

// 事件块主文案（日/周/月三视图统一）
// 画布真值：mine →「我的预定 · EX2」；其余 →「<负责人> · <实验号>[ <短标签>]」
//   例：9/29 王强 · EX1 拉伸（70:203）· 9/28 李娜 · EX3（70:203）· 10/1 维护 · 国庆检定
export function bookingLabel(ev) {
  const tail = ev.relatedExp || ev.title
  if (ev.type === 'mine') return `我的预定 · ${tail}`
  const base = `${ev.owner} · ${tail}`
  return ev.short ? `${base} ${ev.short}` : base
}

// 月视图 chip 文案（画布 70:418 格内标签比周/日视图更短）：
//   occupied    →「<负责人> · <实验号>」（**不带** short 后缀，如 9/29「王强 · EX1」）
//   mine        →「我的预定」（**不带**实验号）
//   maintenance → 标题原文（如「检定」/「国庆检定」）
export function bookingLabelShort(ev) {
  if (ev.type === 'mine') return '我的预定'
  if (ev.type === 'maintenance') return ev.title
  return `${ev.owner} · ${ev.relatedExp || ev.title}`
}

// 关联实验下拉选项（新建预定表单）
export const relatedExperiments = [
  { id: 'EX1', name: '硅胶配方与固化体系筛选' },
  { id: 'EX2', name: '表面处理与底涂适配性' },
  { id: 'EX3', name: '500h 蒸汽老化可靠性验证' },
  { id: 'EX4', name: 'PP 配方验证' }
]

export const DEFAULT_APPROVER = '王强'

// ============================================================
// 日历算法
// ============================================================
export function pad(n) {
  return String(n).padStart(2, '0')
}
export function ymd(d) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}
export function parseYMD(s) {
  const [y, m, d] = s.split('-').map(Number)
  return new Date(y, m - 1, d)
}
export function addDays(d, n) {
  const r = new Date(d)
  r.setDate(r.getDate() + n)
  return r
}
export function sameDay(a, b) {
  return ymd(a) === ymd(b)
}
// 周一为一周起点
export function startOfWeek(d) {
  const r = new Date(d.getFullYear(), d.getMonth(), d.getDate())
  const wd = (r.getDay() + 6) % 7 // 0=周一
  return addDays(r, -wd)
}
export function getWeekDays(ref) {
  const start = startOfWeek(ref)
  return Array.from({ length: 7 }, (_, i) => addDays(start, i))
}
// 月历矩阵：返回若干周（每周 7 天），含上/下月补齐
// 周数按「末周周日已越过当月最后一天」收口 —— 2026-09 为 5 周（画布 70:418 亦为 5 周），
// 原判据要求末周周日仍属当月，会多出一整周灰格。
export function getMonthMatrix(ref) {
  const first = new Date(ref.getFullYear(), ref.getMonth(), 1)
  const start = startOfWeek(first)
  const lastDay = new Date(ref.getFullYear(), ref.getMonth() + 1, 0)
  const weeks = []
  let cur = start
  for (let w = 0; w < 6; w++) {
    const week = []
    for (let i = 0; i < 7; i++) week.push(addDays(cur, w * 7 + i))
    weeks.push(week)
    if (ymd(week[6]) >= ymd(lastDay)) break
  }
  return weeks
}
// 'HH:mm' -> 距零点分钟数
export function hmToMinutes(s) {
  const [h, m] = s.split(':').map(Number)
  return h * 60 + m
}
// 分钟数 -> 竖向像素偏移（相对 HOUR_START）
export function minutesToY(min) {
  return ((min - HOUR_START * 60) / 60) * PX_PER_HOUR
}
// 中文短星期（周一为首）
export const WEEKDAY_CN = ['一', '二', '三', '四', '五', '六', '日']

// 取某设备在某日期的事件（按开始时间升序）
export function bookingsOn(deviceId, dateStr) {
  return bookings
    .filter((b) => b.deviceId === deviceId && b.date === dateStr)
    .sort((a, b) => hmToMinutes(a.start) - hmToMinutes(b.start))
}

// 给组件注入新预定（演示用：返回新事件对象，调用方 push 进响应式列表）
export function makeBooking({ deviceId, date, start, end, relatedExp, purpose }) {
  return {
    id: 'B' + Date.now(),
    deviceId,
    title: purpose || '新预定',
    owner: '王强',
    type: 'mine',
    date,
    start,
    end,
    relatedExp,
    approver: DEFAULT_APPROVER
  }
}
