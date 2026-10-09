// ============================================================
// 演示数据 — 全部取自 Ardot 画布 V1.22 真值（严禁臆造）
// 节点对照：
//   项目列表 4:341 ~ 4:374 · 项目基础信息 4:1437 / 4:1438
//   实验详情 4:525（导航 4:582 + 子页签 70:1 + 配方优化 70:11）
//   实验设计聚焦视图 4:641 · 任务详情 4:718
//   工作台 4:118 · 实验记录本 4:899
// ============================================================

// ------------------------------------------------------------
// 项目列表（10 列：选择 / 星标 / 名称 / ID / 状态 / 截止日期 /
//           负责人 / 已完成实验 / 访问权限 / 操作）
// 画布 4:341 行-高温硅胶 / 4:352 行-PP低气味 /
//      4:363 行-聚硅氮烷涂层 / 4:374 行-涂层中试
// ------------------------------------------------------------
export const projects = [
  {
    // 与真机 payload 同形（V1.32）：id = 数字主键（下钻/选中/请求参数用它），
    // code = PrefixedIdModel#code = PR<id>（**只**用于 ID 列显示）——两者不得互换。
    id: '1025240',
    code: 'PR1025240',
    folder: false,
    name: '150°C 蒸汽环境金属粘接用高温硅胶研究',
    starred: true,
    status: 'active', // active 进行中 / notstarted 未开始 / done 已完成
    due: '2026-09-30',
    owner: { name: '张负责人', initial: '张', color: 'blue' },
    completed: 1,
    total: 3,
    members: [
      { initial: '张', color: 'blue' },
      { initial: '王', color: 'green' },
      { initial: '刘', color: 'orange' }
    ],
    extra: 2
  },
  {
    // 与真机 payload 同形（V1.32）：id = 数字主键（下钻/选中/请求参数用它），
    // code = PrefixedIdModel#code = PR<id>（**只**用于 ID 列显示）——两者不得互换。
    id: '1025241',
    code: 'PR1025241',
    folder: false,
    name: 'PP 汽车内饰件低气味配方开发',
    starred: false,
    status: 'active',
    due: '2026-10-15',
    owner: { name: '张负责人', initial: '张', color: 'blue' },
    completed: 1,
    total: 2,
    members: [
      { initial: '张', color: 'blue' },
      { initial: '王', color: 'green' },
      { initial: '李', color: 'cyan' }
    ],
    extra: 0
  },
  {
    // 与真机 payload 同形（V1.32）：id = 数字主键（下钻/选中/请求参数用它），
    // code = PrefixedIdModel#code = PR<id>（**只**用于 ID 列显示）——两者不得互换。
    id: '1025242',
    code: 'PR1025242',
    folder: false,
    name: '聚硅氮烷模具陶瓷涂层工艺开发',
    starred: false,
    status: 'notstarted',
    due: '2026-07-31',
    owner: { name: '张负责人', initial: '张', color: 'blue' },
    completed: 2,
    total: 4,
    members: [
      { initial: '张', color: 'blue' },
      { initial: '刘', color: 'orange' },
      { initial: '赵', color: 'purple' }
    ],
    extra: 0
  },
  {
    // 与真机 payload 同形（V1.32）：id = 数字主键（下钻/选中/请求参数用它），
    // code = PrefixedIdModel#code = PR<id>（**只**用于 ID 列显示）——两者不得互换。
    id: '1025243',
    code: 'PR1025243',
    folder: false,
    name: '聚硅氮烷陶瓷涂层中试放大与验证',
    starred: false,
    status: 'done',
    due: '2026-06-30',
    owner: { name: '张负责人', initial: '张', color: 'blue' },
    completed: 1,
    total: 1,
    members: [
      { initial: '张', color: 'blue' },
      { initial: '李', color: 'cyan' }
    ],
    extra: 0
  },
  // 文件夹行（V1.32 / spec SCN-PROJ-LIST-7）—— 与真机 payload 同形：
  //   folder: true 是行类型判别字段（原生 Lists::ProjectAndFolderSerializer#folder 同名字段），
  //   id = 数字主键（drillUrl 用它）、code = PF<id>（只用于 ID 列显示）、
  //   folderInfo = 「x 个项目 | y 个文件夹」。
  // ⚠ 原型独立跑时 mock 是唯一数据源，这里**必须**放一行文件夹行 —— 否则文件夹相关的
  //   渲染/菜单/面包屑在 npm run dev 下永远走不到，等于没做。
  // ⚠ drillUrl 给**真机形态**（带 project_folder_id）。原型 SPA 没有 /eln_project_list
  //   这条路由，点了会是 404 —— 这是**有意为之**：不编一个原型假路由出来，
  //   免得"原型能点、真机 404"那种只在真机上才暴露的偏差。
  {
    id: '902',
    code: 'PF902',
    folder: true,
    name: '150°C 蒸汽粘接（历史归档）',
    folderInfo: '3 个项目 | 1 个文件夹',
    archived: false,
    starred: false,
    status: null,
    startDate: null,
    due: null,
    owner: { name: '—', initial: '·', color: 'blue' },
    completed: 0,
    total: 0,
    tasksCompleted: 0,
    tasksTotal: 0,
    commentsCount: 0,
    description: null,
    createdAt: null,
    updatedAt: null,
    archivedOn: null,
    folderId: null,
    members: [],
    extra: 0,
    drillUrl: '/eln_project_list?project_folder_id=902',
    // 行菜单：**文件夹专属集合**（编辑/移动/删除）。原型不发请求，端点留空 =
    // 显式留白（点了会在列表页顶部报「原生端点未就绪」，不是静默无反应）。
    actions: {
      edit: { enabled: false, method: 'PATCH', url: null },
      move: { enabled: false, method: 'POST', url: null },
      delete: { enabled: false, method: 'POST', url: null }
    }
  }
]

// 状态文案映射（中文）
export const statusLabel = {
  active: '进行中',
  notstarted: '未开始',
  done: '已完成'
}

// 头像配色（画布 4:1202 起 5 个角色色调）
export const avatarPalette = {
  blue: { bg: '#DBEAFE', fg: '#2563EB' },
  green: { bg: '#E7F7E9', fg: '#047857' },
  orange: { bg: '#FCF2E3', fg: '#B45309' },
  purple: { bg: '#E9DFF6', fg: '#6D28D9' },
  cyan: { bg: '#E3F6F7', fg: '#0E7490' }
}

// ------------------------------------------------------------
// 项目基础信息（画布 4:1437 左列 / 4:1438 右列 / 4:1457 描述）
// 默认项目 = PR1025240
// ------------------------------------------------------------
export const projectBasic = {
  name: '150°C 蒸汽环境金属粘接用高温硅胶研究',
  code: 'PR1025240',
  span: '2026-03-02 ~ 2026-09-30',
  source: '国家重点研发计划',
  foundedAt: '2026-03-02',
  owner: '张负责人（Owner）',
  team: '高分子材料研究组',
  status: '执行中',
  metricProgress: '指标 2/3 达标',
  description:
    '面向 150°C 蒸汽环境下的金属粘接需求，筛选耐高温加成型硅胶体系（首选 Dow ADH-6066），' +
    '通过配方与固化工艺优化，达成连续 500h 蒸汽老化后剪切强度保留率 ≥ 75% 的目标。'
}

// 项目成员表（5 人，头衔沿用画布成员页签口径）
export const members = [  { name: '张负责人', title: '项目负责人', role: 'Owner', joined: '2026-03-02', color: 'blue' },
  { name: '王组长', title: '小组组长', role: 'Normal user', joined: '2026-03-05', color: 'green' },
  { name: '刘组长', title: '小组组长', role: 'Normal user', joined: '2026-03-10', color: 'orange' },
  { name: '李组员', title: '组员', role: 'Technician', joined: '2026-04-01', color: 'cyan' },
  { name: '赵组长', title: '小组组长', role: 'Technician', joined: '2026-04-15', color: 'purple' }
]

// 项目花费（画布 79:11「页签内容-项目花费」为 hidden 态）
// 总额与材料/测试表征的结构比例取自**画布** 4:213「项目总花费」卡的比例。
// ⚠ V1.27：工作台那张「项目总花费」KPI 卡已删除（改为「参与项目」），但**本块是项目详情页的
//   花费数据，与工作台卡无关**，比例仍以画布 4:213 为准 —— 勿随工作台卡一并清理。
export const projectCost = {
  total: '¥86.4万',
  splits: [
    { label: '材料（原生任务消耗）', amount: '¥55.3万', share: '64%', tone: 'primary' },
    { label: '测试表征（服务执行）', amount: '¥31.1万', share: '36%', tone: 'purple' }
  ],
  scopes: [
    { key: 'project', label: '仅项目' },
    { key: 'user', label: '仅用户' },
    { key: 'both', label: '项目 × 用户' }
  ],
  rows: [
    {
      category: '材料',
      source: '原生 RepositoryLedgerRecord（reference_type = MyModuleRepositoryRow）',
      basis: 'amount × 快照单价 unit_price',
      amount: '¥55.3万',
      share: '64%'
    },
    {
      category: '测试表征',
      source: '二开 REQ-RES-CONSUME 消耗/执行明细表',
      basis: '审批表单次数 × 服务档案快照单价',
      amount: '¥31.1万',
      share: '36%'
    }
  ],
  note:
    '口径：按 project_id 汇总 REQ-RES-CONSUME（花费核算唯一对外数据源）；材料行由原生任务消耗同步登记、与 Ledger 一一对应，' +
    '服务行不写 Ledger；由 RepositoryTemplate.equipment 创建的库存一律不计花费（SCN-RES-COST-6）；入库采购额不计入。'
}

// 项目指标（页头标签「指标 2/3 达标」画布 63:4 → 条数 3、达标 2）
// 第 1/2 项直接取自任务成果卡（画布 4:1053/4:1054、4:1056/4:1057）；第 3 项取自项目描述目标（画布 4:1459）
export const projectMetrics = [
  { name: '拉伸剪切强度', target: '≥ 8.0 MPa', current: '7.4 MPa', ok: false },
  { name: '老化后失效模式（内聚破坏占比）', target: '≥ 80%', current: '100%', ok: true },
  { name: '500h 蒸汽老化后剪切强度保留率', target: '≥ 75%', current: '82%', ok: true }
]

// ------------------------------------------------------------
// 项目文档（画布 4:1460 hidden 态）
// ⚠ 2026-10-04：这两组原先**写死在 ProjectDetail.vue 的 <script setup> 里**，
//   嵌入态根本覆盖不掉 —— 真机上就一直显示「李组员 / 刘组长 / 底涂剂选型对比测试报告」
//   这类原型演示值（用户报的「下钻数据未接入真实数据」其中一处）。
//   挪到 mock 之后，嵌入态由注入替换；原生没有项目文档模型 → 注入空数组 → 组件走空态。
// ------------------------------------------------------------
export const requiredDocs = [
  { name: '立项申请材料', ver: 'v2', date: '2026-03-02', uploaded: true },
  { name: '项目任务书', ver: 'v2', date: '2026-03-02', uploaded: true },
  { name: '年度计划', ver: 'v2', date: '2026-03-16', uploaded: true },
  { name: '年度报告', ver: '—', date: '—', uploaded: false },
  { name: '结题报告', ver: '—', date: '—', uploaded: false }
]

export const otherDocs = [
  { name: '底涂剂选型对比测试报告.pdf', type: '执行', by: '李组员', date: '2026-09-28' },
  { name: '原材料 COA 汇总.xlsx', type: '执行', by: '李组员', date: '2026-05-06' },
  { name: '中期评审报告.pptx', type: '评审', by: '刘组长', date: '2026-06-20' }
]

// 任务关闭审核汇总（报告 §5 第 6 项 #11 · spec REQ-PM-INDICATOR / SCN-PM-IND-3/4/5）
// 真机由 payload.taskCloseReview 覆写；嵌入态无对应数据源 → 走空态（不回落演示值）。
export const taskCloseReview = {
  total: 0,
  closed: 0,
  pending: 0,
  rejected: 0,
  indicatorDriven: false,
  tasks: []
}

// 项目归档导出（报告 §5 第 6 项 #10 · spec SCN-PM-ARCH-1/2/3）
// 真机由 payload.projectArchive 覆写（复用原生 archived 状态 + 导出端点）；嵌入态无 → 空态。
export const projectArchive = {
  archived: false,
  archivedAt: null,
  canExport: false,
  exportUrl: ''
}

// ------------------------------------------------------------
// 实验（画布 4:525 面包屑 / 4:641 面包屑）
// EX1 · 硅胶配方与固化体系筛选
// ------------------------------------------------------------
export const experiments = [
  {
    id: 'EX1',
    code: 'EX1',
    name: '硅胶配方与固化体系筛选',
    fullName: 'EX1 · 硅胶配方与固化体系筛选',
    status: 'active',
    owner: { name: '张负责人', initial: '张', color: 'blue' },
    progress: { done: 1, total: 3 },
    due: '2026-09-30'
  },
  {
    id: 'EX2',
    code: 'EX2',
    name: '表面处理与底涂适配性',
    fullName: 'EX2 · 表面处理与底涂适配性',
    status: 'active',
    owner: { name: '王组长', initial: '王', color: 'green' },
    progress: { done: 0, total: 2 },
    due: '2026-10-15'
  },
  {
    id: 'EX3',
    code: 'EX3',
    name: '500h 蒸汽老化可靠性验证',
    fullName: 'EX3 · 500h 蒸汽老化可靠性验证',
    status: 'notstarted',
    owner: { name: '刘组长', initial: '刘', color: 'orange' },
    progress: { done: 0, total: 4 },
    due: '2026-11-30'
  }
]

// 实验详情 · 左栏竖向导航（画布 4:582 仅 2 项）
export const expNav = [
  { key: 'overview', label: '实验概况' },
  { key: 'tasks', label: '实验任务' }
]

// 实验概况 · 子页签栏（画布 70:1 共 4 项）
export const expSubTabs = [
  { key: 'info', label: '实验信息' },
  { key: 'purpose', label: '实验目的' },
  { key: 'method', label: '实验方案与方法' },
  { key: 'design', label: '实验设计与配方优化' }
]

// 实验设计与配方优化 · DV 设计变量表（画布 4:605 表头 / 4:614 行1 / 4:623 行2）
export const expDesignVars = [
  { name: '硅胶基料 A 组分占比', type: '连续', range: '60 ~ 85 phr', constraint: '单调递增' },
  { name: '固化剂用量', type: '连续', range: '0.5 ~ 2.0 phr', constraint: '上限 2.0' }
]

// 实验任务（画布 4:71 任务详情 + 4:226/4:238 待办口径）
//
// ⚠ `experimentId` 必须跟着任务一起给：宿主把任务挂在实验之下，真实路由是
//   `/experiments/:experiment_id/my_modules/:id/eln_task_detail` 两级。
//   drillTo(t,'task') 在 payload 未下发 detailUrl 时（原型独立跑）要靠这个字段
//   拼回落路径；缺了它只能返回空串（宁可不给链接，也不编一个指向别人实验的假 id）。
export const tasks = [
  {
    id: 'MD-01',
    experimentId: 'EX1',
    name: '底涂剂选型对比实验',
    status: 'pendingReview',
    owner: { name: '李组员', initial: '李', color: 'cyan' },
    due: '2026-10-05',
    completed: 1,
    total: 1
  },
  {
    id: 'MD-02',
    experimentId: 'EX1',
    name: '基料 A 组分梯度配比与固化',
    status: 'active',
    owner: { name: '李组员', initial: '李', color: 'cyan' },
    due: '2026-10-12',
    completed: 0,
    total: 1
  },
  {
    id: 'MD-03',
    experimentId: 'EX1',
    name: '低温冲击样条制备与测试',
    status: 'pendingReview',
    owner: { name: '王组长', initial: '王', color: 'green' },
    due: '2026-10-08',
    completed: 0,
    total: 1
  }
]

// 任务状态文案（画布 4:849 流程轨迹口径）
export const taskStatusLabel = {
  pending: '待接收',
  active: '进行中',
  submitted: '提交完成申请',
  pendingReview: '待审核',
  closed: '已关闭'
}

// ------------------------------------------------------------
// 任务详情 · 底涂剂选型对比实验（画布 4:718 全页真值）
// ------------------------------------------------------------
export const taskDetail = {
  name: '底涂剂选型对比实验',
  status: 'pendingReview',
  experiment: 'EX1 · 硅胶配方与固化体系筛选',
  purpose: '在 5 种底涂剂中筛选与 150°C 蒸汽老化兼容性最好的方案，为后续配方定型提供界面处理依据',
  plan:
    '1) 基材打磨除油 → 2) 底涂剂涂覆并固化 → 3) 硅胶粘接 → 4) 150°C 蒸汽老化 500h → 5) 拉伸剪切强度测试',
  properties: [
    { key: '当前状态', value: '待审核', kind: 'chip' },
    { key: '指派组员', value: '李组员', kind: 'strong' },
    { key: '上级实验', value: 'EX1', kind: 'mono' },
    { key: '接收时间', value: '09-22 10:12', kind: 'mono' },
    { key: '完成申请', value: '09-28 09:40', kind: 'mono' },
    { key: '截止日期', value: '10-05', kind: 'warn' }
  ],
  notes: [
    {
      author: '李组员',
      time: '09-26 14:20',
      type: '实验操作',
      body:
        '完成 5 种底涂剂（A/B/C/D/E）的涂覆与固化，固化条件 150°C × 30 min。' +
        '基材为 6061 铝，表面先经 240 目砂纸打磨并丙酮除油。',
      attachments: ['底涂固化照片.jpg', '固化工艺参数.xlsx']
    },
    {
      author: '李组员',
      time: '09-28 09:05',
      type: '测试数据',
      body: '500h 蒸汽老化后拉伸剪切强度测试完成，B 底涂剂组表现最佳（7.4 MPa），无界面剥离。',
      chart: {
        title: '拉伸剪切强度 / MPa（500h 蒸汽老化后，n=3）· B 组为当前最优',
        bars: [
          { label: 'A', value: 6.8, width: 270 },
          { label: 'B', value: 7.4, width: 295, best: true },
          { label: 'C', value: 5.9, width: 235 },
          { label: 'D', value: 4.6, width: 185 },
          { label: 'E', value: 3.2, width: 130 }
        ]
      },
      ai: 'AI 建议：B 组数据较 A 组提升 8.8%，建议第 4 轮优先复验 B 组一致性（n=3）'
    }
  ],
  formFields: [
    { label: '底涂剂型号', value: 'B（钛酸酯偶联型）' },
    { label: '涂覆厚度 / mm', value: '0.05' },
    { label: '剪切强度 / MPa', value: '7.4', active: true }
  ],
  conclusion:
    '在 5 种底涂剂中，B（钛酸酯偶联型）经 500h 蒸汽老化后剪切强度最高（7.4 MPa），' +
    '失效模式为 100% 内聚破坏，界面粘接可靠；D/E 组出现界面剥离，不建议采用。',
  metrics: [
    { name: '拉伸剪切强度 ≥ 8.0 MPa', result: '实测 7.4 MPa · 未达标', ok: false },
    { name: '内聚破坏占比 ≥ 80%', result: '100% · 达标', ok: true }
  ],
  outputs: ['底涂剂对比测试报告.pdf', '老化前后对照照片.zip'],
  nextStep:
    '下一步：提交项目负责人审核 → 通过后任务关闭并进入项目归档；未通过则退回组员补充复验（n=3）',
  flow: [
    { title: '组长派发任务', sub: '王组长 · 09-22 10:12', color: 'done' },
    { title: '组员接收并开始执行', sub: '李组员 · 09-22 11:30', color: 'done' },
    { title: '提交完成申请', sub: '李组员 · 09-28 09:40', color: 'purple' },
    { title: '等待项目负责人审核', sub: '当前节点 · 已等待 4 小时', color: 'current' },
    { title: '审核通过 → 任务关闭', sub: '未开始', color: 'todo' }
  ],
  resources: [
    { name: 'B 底涂剂（天津金汇）', value: '200 mL' },
    { name: '6061 铝试片', value: '30 片' },
    { name: '万能试验机（共享）', value: '已预约 09-28', ok: true }
  ],
  linkedMetrics: [
    { name: '拉伸剪切强度', value: '进行中 · 60%', tone: 'warn' },
    { name: '老化后失效模式', value: '已完成 · 100%', tone: 'done' }
  ],
  comments: [
    { author: '王组长', time: '09-28 10:20', body: '数据不错，请把 D 组界面剥离的照片一并补充进记录本，便于审核判断。' },
    { author: '张负责人', time: '09-28 11:05', body: '收到，审核时一并确认，若达标即关闭任务。' }
  ]
}

// 实验设计迭代记录
// 画布 4:70 推荐条件 R1/R2/R3 + 4:681 迭代记录看板（行1 4:694 / 行2 4:705）
export const designRecommendations = [
  { round: '推荐条件 R1 · 第 8 轮', cond: '基料 A 72 phr · 固化剂 1.2 phr', predict: '预测剪切强度 8.4 MPa · 置信 0.86', best: true },
  { round: '推荐条件 R2 · 第 7 轮', cond: '基料 A 78 phr · 固化剂 1.6 phr', predict: '预测剪切强度 8.1 MPa · 置信 0.81' },
  { round: '推荐条件 R3 · 第 6 轮', cond: '基料 A 68 phr · 固化剂 0.9 phr', predict: '预测剪切强度 7.6 MPa · 置信 0.74', muted: true }
]

export const iterations = [
  {
    round: '第 6 轮',
    method: '贝叶斯优化',
    inputs: 'A 68 phr · 固化剂 0.9 phr · 厚度 1.5 mm',
    recommend: '预测 7.6 MPa · 置信 0.74',
    result: '实测 7.4 MPa',
    resultTone: 'done'
  },
  {
    round: '第 8 轮',
    method: '贝叶斯优化',
    inputs: 'A 72 phr · 固化剂 1.2 phr · 厚度 1.5 mm',
    recommend: '预测 8.4 MPa · 置信 0.86',
    result: '验证任务生成',
    resultTone: 'warn'
  }
]

// ------------------------------------------------------------
// 工作台（画布 4:118）
// ------------------------------------------------------------
export const workbenchMeta = {
  greeting: '下午好，张负责人',
  role: '项目负责人 · Owner',
  updatedAt: '数据更新于 14:32',
  notice: '3 条未读通知：任务待审核 2 · 资源申请待终审 1 · 云版 Token 余额预警 1',
  // 状态机说明：原型独立跑用画布演示标签兜底；
  // 真机由后端下发**数据库里真实的 MyModuleStatus 名**（组件内不硬编，见 panel-sub）
  statusMachine: '状态机：待接收 / 进行中 / 提交完成申请 / 待审核 / 已关闭'
}

// ⚠ V1.25：KPI 卡的下钻目标与 addons/workbench 的 payload **同契约**（SCN-DASH-8）：
//   `to`     = 跳转目标（整页跳转）
//   `anchor` = 本页内目标卡的 DOM id（页内滚动）
//   两者都没有 = 原生无承载面 → 显式留白（卡片保持不可点）。
//
//   ★ V1.25 路径词汇表统一：`to` 的**取值两种模式也相同**了 —— 一律是宿主
//     SciNote 真实路由（`/eln_project_list`、`/eln_res_center?tab=cost`）。
//     原因：SPA 路由表已改用宿主路径注册（src/router/index.js），所以同一串
//     路径在 SPA 态能命中页内路由、在内嵌态由 HostRouterLink 透传给 Rails。
//     ⚠ 别再退回「原型用 /projects、真机用 /eln_project_list」的双词汇表写法：
//       那个分裂正是「改了一侧忘了另一侧 → 点击静默无反应 / 真机 404」的根因。
//     宿主**没有**承载面的页面（如报表中心 `/reports`）仍用原型短路径，且在
//     src/router/index.js 里明确登记为「原型独有」。
//   真机 payload 不输出「云版 Token」卡（私有化部署），故这里也不给它目标。
export const workbenchKpis = [
  { label: '小组数', value: '4', trend: '覆盖 18 名组员', anchor: 'eln-wb-groups' },
  { label: '项目任务', value: '126', trend: '进行中 38 · 待审核 2', tone: 'warn', to: '/eln_project_list' },
  // V1.27：第三张卡由「项目总花费」改为「参与项目」。
  //   · value = 参与项目数；trend = 「其中我负责 M 个」；M=0 时真机留空串（mock 给非 0 演示值）。
  //   · to = 宿主项目列表页 + 成员筛选 + 显式 view_mode=active（与真机 payload 逐字同形）。
  //   ⚠ mock 用**宿主路径**是正确的（V1.26 起前端只有一套路径词汇表）；
  //     HostRouterLink 对含 /eln_ 的 to 原样透传，query 串随之带出。
  { label: '参与项目', value: '12', trend: '其中我负责 5 个', to: '/eln_project_list?filters%5Bmembers%5D%5B%5D=1&view_mode=active' },
  { label: '云版 Token 剩余', value: '62%', trend: '按当前用量约 18 天耗尽', tone: 'warn' }
]

export const workbenchTodos = [
  { type: '任务审核', title: '低温冲击样条制备与测试 · 等待审核关闭', due: '10-08', status: '待审核', tone: 'warn' },
  { type: '资源终审', title: 'POE 增韧剂采购申请 · 小组组长已初审', due: '10-12', status: '待终审', tone: 'purple' },
  { type: '实验设计', title: '冲击韧性 DOE 第三轮推荐条件待验证', due: '09-30', status: '待处理', tone: 'primary' }
]

// 任务状态分布（画布 4:245 条形图，比例按最大值 68 归一）
export const workbenchDist = [
  { label: '待接收', num: 12, color: '#A1A1AA' },
  { label: '进行中', num: 38, color: '#3B82F6' },
  { label: '提交完成申请', num: 6, color: '#7C3AED' },
  { label: '待审核', num: 2, color: '#F59E0B' },
  { label: '已关闭', num: 68, color: '#10B981' }
]

export const workbenchGroups = [
  { name: '一组 · 增韧体系', leader: '王组长', rate: '82%', tone: 'done' },
  { name: '二组 · 填料分散', leader: '刘组长', rate: '76%', tone: 'warn' },
  { name: '三组 · 测试表征', leader: '赵组长', rate: '64%', tone: 'warn' }
]

//   真机 payload 的 to 同样是宿主真实路由（WorkbenchPayload#entries_block
//   走 Rails path helper）—— 本轮统一后两侧字面值也一致了。
//   ⚠ 「报表中心」是**原型独有**页面（宿主无承载面），故保留原型短路径 /reports，
//     并在 src/router/index.js 登记；真机 payload 不下发这个入口。
export const workbenchEntries = [
  { label: '新建实验任务', to: '/experiments/EX1/eln_exp_detail' },
  { label: '项目管理', to: '/eln_project_list' },
  { label: '资源中心', to: '/eln_res_center' },
  { label: '报表中心', to: '/reports' }
]

// ------------------------------------------------------------
// 工作台（画布 4:66 / 4:293）—— 真机注入容器
//
// 上面六块 workbench* 是**画布演示默认值**：原型独立跑（npm run dev、无 SciNote
// 注入）时仍能渲染完整页面，便于离线验收。
// 真机（/eln_workbench）由 addons/workbench 的 WorkbenchPayload 实时读库下发，
// workbench.js 把注入值塞进下面这个容器，组件只读这个容器 —— 组件里再没有任何
// 写死的宿主路由 / 色值 / 演示文案。
//
// ⚠ 铁律：组件内不能有「要能被 payload 覆盖的常量」。所以这里连
//   meta.statusMachine（状态机说明，原来是模板里硬编的五个演示标签）也统一走容器。
// ============================================================
export const workbenchPayload = {
  meta: { ...workbenchMeta },
  kpis: [...workbenchKpis],
  todos: [...workbenchTodos],
  dist: [...workbenchDist],
  groups: [...workbenchGroups],
  entries: [...workbenchEntries]
}

// ------------------------------------------------------------
// 实验记录本（画布 4:72 / 4:899）
// 记录流按「任务」分组（画布 4:938 分组头-EX1），3 条记录即画布 4:941/4:954/4:1064
// ------------------------------------------------------------
export const notebookRecords = [
  {
    id: 'N-01',
    type: '测试数据',
    dot: 'blue',
    author: '李组员',
    date: '09-28 09:05',
    body: '500h 蒸汽老化后拉伸剪切强度测试完成，B 底涂剂组表现最佳（7.4 MPa）。',
    path: '底涂剂选型对比实验 · EX1 · 高温硅胶项目'
  },
  {
    id: 'N-02',
    type: '异常记录',
    dot: 'red',
    author: '陈组员',
    date: '09-27 16:40',
    body: 'D 组试片在老化 120h 后出现局部剥离，怀疑底涂剂固化不完全，已重做并调整固化升温曲线。',
    path: '底涂剂选型对比实验 · EX1 · 高温硅胶项目'
  },
  {
    id: 'N-03',
    type: '结论与评审',
    dot: 'purple',
    author: '王组长',
    date: '09-26 18:10',
    body: '阶段评审结论：底涂剂方案以 B 为主选，C 为备选；下一阶段进入硅胶本体配方与固化体系的正交优化。',
    path: 'EX2 · 表面处理与底涂适配性 · 高温硅胶项目'
  }
]

// 记录流分组头（画布 4:938 / 4:940）
export const notebookGroups = [
  { name: 'EX1 · 硅胶配方与固化体系筛选', count: '6 条记录 · 2 位组员' }
]

// 顶部指标条（画布 4:925~4:937）
export const notebookStats = [
  { label: '记录总数', value: '87', tone: 'default' },
  { label: '本周新增', value: '23', tone: 'primary' },
  { label: '异常记录', value: '4', tone: 'danger' },
  { label: '待审核归档', value: '2', tone: 'warn' }
]

// 记录本目录（画布 4:991，level 0 = 项目 / 1 = 实验）
export const notebookCatalog = [
  { name: '150°C 蒸汽环境金属粘接用高温硅胶研究', count: '6 条', level: 0 },
  { name: 'EX1 · 硅胶配方与固化体系筛选', count: '4 条', level: 1 },
  { name: 'EX2 · 表面处理与底涂适配性', count: '2 条', level: 1 },
  { name: 'PP 汽车内饰件低气味配方开发', count: '3 条', level: 0 }
]

// 记录类型分布（画布 4:1005，色值取画布点 fills）
export const notebookTypeDist = [
  { label: '实验操作', num: '42 · 48%', color: '#A1A1AA', tone: 'default' },
  { label: '测试数据', num: '28 · 32%', color: '#F59E0B', tone: 'default' },
  { label: '异常记录', num: '4 · 5%', color: '#EF4444', tone: 'danger' },
  { label: '结论与评审', num: '13 · 15%', color: '#7C3AED', tone: 'default' }
]

// 筛选胶囊（画布 4:914 / 4:916 / 4:918 / 4:920，共 4 个）
export const notebookFilters = ['全部', '实验操作', '测试数据', '异常记录']

// ============================================================
// 资源中心（ELN系统-Vue3/src/views/ResCenter.vue + ResApplyDetail.vue）
// ------------------------------------------------------------
// 真机部署时由 src/entries/res_center.js / apply_detail.js 覆写：
//   入口只读 window.__ELN_RES_CENTER__ / window.__ELN_APPLY_DETAIL__，
//   把真值塞进下面这两个可变容器，组件 mount 时直接读出来作为初始值。
//
// 这里的 prototype 默认值是 V1.22 画布演示值 —— 原型独立跑（无 SciNote 注入）
// 时仍能渲染完整页面，便于离线验收。
// ============================================================

export const resCenterPayload = {
  inventory: {
    // 资源台账 tab 完全采用原生 Inventories：这里只列可访问的原生库存库入口
    repositories: [
      { id: 1, name: '化学品与试剂', description: '原生库存模板：化学品与试剂（含 Stock 与有效期）', rowsCount: 3 },
      { id: 2, name: '设备仪器', description: '原生库存模板：设备仪器（设备模板库存不计花费）', rowsCount: 2 }
    ]
  },
  ledger: {
    // 出入库记录页签的筛选（类型 / 项目 / 操作人 / 日期范围）候选由前端从这批行里抽，
    // 所以这里刻意铺开三个维度：两种类型、三个出库项目、三个操作人 —— 独立跑时
    // 每个下拉都筛得出东西，不会出现「选了却空表」看不出效果的情况。
    records: [
      { time: '2026-09-12 10:24', type: '出库', name: 'PP 基料 K8003', qty: '20 kg', price: '¥ 350 / kg', project: '高温硅胶研究', user: '张伟' },
      { time: '2026-09-12 09:40', type: '出库', name: '滑石粉 HTP05', qty: '3 kg', price: '¥ 12 / kg', project: 'PP 配方开发', user: '李娜' },
      { time: '2026-09-01 09:12', type: '入库', name: 'PP 基料 K8003（采购到货）', qty: '100 kg', price: '¥ 350 / kg', project: '—（入库不写项目）', user: '李娜' },
      { time: '2026-08-28 11:15', type: '出库', name: 'POE 增韧剂 8150', qty: '5 kg', price: '¥ 420 / kg', project: '高温硅胶研究', user: '张伟' },
      { time: '2026-08-27 16:05', type: '入库', name: '滑石粉 HTP05（采购到货）', qty: '50 kg', price: '¥ 12 / kg', project: '—（入库不写项目）', user: '王强' },
      { time: '2026-08-26 14:32', type: '出库', name: '抗氧剂 1010', qty: '0.5 kg', price: '¥ 96 / kg', project: '阻燃 PP 开发', user: '王强' }
    ]
  },
  consume: {
    rows: [
      { time: '2026-09-12 10:24', type: '物资', name: 'PP 基料 K8003', qty: '20 kg', price: '¥ 350 / kg', amount: '¥ 7,000', project: '高温硅胶研究', user: '张伟', status: '—' },
      { time: '2026-09-08 14:10', type: '服务', name: 'DSC 差示扫描量热', qty: '2 次', price: '¥ 600 / 次', amount: '¥ 1,200', project: 'PP 配方开发', user: '李娜', status: '已结算' },
      { time: '2026-09-05 09:30', type: '服务', name: '万能材料试验机（拉伸）', qty: '3 次', price: '¥ 200 / 次', amount: '¥ 600', project: 'PP 配方开发', user: '王强', status: '待验收' },
      { time: '2026-08-28 11:15', type: '物资', name: 'POE 增韧剂 8150', qty: '5 kg', price: '¥ 420 / kg', amount: '¥ 2,100', project: '高温硅胶研究', user: '张伟', status: '—' }
    ],
    // 筛选下拉选项：真机由 payload.consume.projects / .users 覆写（带 id，供导出回传）
    projects: [],
    users: []
  },
  apply: {
    rows: [
      { id: 1, no: 'SQ-2026-0092', type: '测试表征 · DSC 差示扫描量热', project: 'PP 配方开发', qty: '2 次', status: '已通过', statusRaw: 'project_approved', user: '李娜', submitterId: 2, time: '2026-09-07 09:20', projectId: 1, kind: 'service' },
      { id: 2, no: 'SQ-2026-0091', type: '材料 · PP 基料 K8003', project: '高温硅胶研究', qty: '20 kg', status: '已完成', statusRaw: 'completed', user: '张伟', submitterId: 1, time: '2026-09-10 14:05', projectId: 2, kind: 'material' },
      { id: 3, no: 'SQ-2026-0093', type: '测试表征 · 万能材料试验机（拉伸）', project: 'PP 配方开发', qty: '3 次', status: '待审批', statusRaw: 'submitted', user: '王强', submitterId: 3, time: '2026-09-09 11:40', projectId: 1, kind: 'service' },
      { id: 4, no: 'SQ-2026-0090', type: '材料 · 滑石粉 TYT-777A', project: '高温硅胶研究', qty: '10 kg', status: '驳回', statusRaw: 'rejected', user: '张伟', submitterId: 1, time: '2026-09-02 16:30', projectId: 2, kind: 'material' }
    ],
    totalCount: 4,
    // 新建申请表单（SCN-RES-APPLY-1）项目下拉：真机由 payload.apply.projects 覆写
    projects: [
      { id: 1, name: 'PP 配方开发' },
      { id: 2, name: '高温硅胶研究' }
    ],
    // 服务档案下拉（SCN-RES-TEST-1）：真机由 payload.apply.serviceCatalogs 下发
    serviceCatalogs: [
      { id: 1, name: 'DSC 差示扫描量热', unitPrice: 600, requiresAcceptance: false },
      { id: 2, name: '万能材料试验机（拉伸）', unitPrice: 200, requiresAcceptance: true },
      { id: 3, name: 'SEM 扫描电镜', unitPrice: 800, requiresAcceptance: false }
    ],
    // 材料类绑定下拉（SCN-RES-APPROVE-3 / SQ-2026-7783）：真机由 payload.apply.repositoryRows /
    // .myModules 下发（只含用户可读范围）。独立预览给一组演示值，好让表单可操作。
    repositoryRows: [
      { id: 101, name: 'PP 基料 K8003', repositoryId: 1, repositoryName: '化学品与试剂' },
      { id: 102, name: 'POE 增韧剂 8150', repositoryId: 1, repositoryName: '化学品与试剂' },
      { id: 103, name: '滑石粉 TYT-777A', repositoryId: 1, repositoryName: '化学品与试剂' }
    ],
    myModules: [
      { id: 201, name: '混料与注塑样条制备', projectId: 1, projectName: 'PP 配方开发' },
      { id: 202, name: '力学性能测试', projectId: 1, projectName: 'PP 配方开发' },
      { id: 203, name: '粘接强度验证', projectId: 2, projectName: '高温硅胶研究' }
    ],
    // 四维筛选候选（Q4-2：客户端过滤用；真机由 payload.apply.filterOptions 下发，只含可见范围）
    filterOptions: {
      statuses: [
        { value: 'draft', label: '草稿' },
        { value: 'submitted', label: '待审批' },
        { value: 'group_approved', label: '小组通过' },
        { value: 'project_approved', label: '已通过' },
        { value: 'rejected', label: '驳回' },
        { value: 'completed', label: '已完成' }
      ],
      types: [
        { value: 'material', label: '材料' },
        { value: 'service', label: '测试表征' }
      ],
      projects: [
        { id: 1, name: 'PP 配方开发' },
        { id: 2, name: '高温硅胶研究' }
      ],
      submitters: [
        { id: 1, name: '张伟' },
        { id: 2, name: '李娜' },
        { id: 3, name: '王强' }
      ]
    },
    // 权限与可见范围（真机由 payload.apply.permissions 下发）
    permissions: {
      scope: 'manage',
      canConfigureApprovers: true,
      manageableProjectIds: [1, 2]
    },
    // 审批人配置面板种子（独立预览无后端时兜底；真机由 GET /eln_project_approvers 覆盖）
    approverSeed: {
      projects: [
        { id: 1, name: 'PP 配方开发' },
        { id: 2, name: '高温硅胶研究' }
      ],
      project: { id: 1, name: 'PP 配方开发' },
      stages: {
        group: { label: '初审', configured: true, users: [{ id: 11, user_id: 3, name: '王强' }] },
        project: { label: '终审', configured: true, users: [{ id: 12, user_id: 1, name: '张伟' }] }
      },
      candidates: [
        { id: 1, name: '张伟' },
        { id: 2, name: '李娜' },
        { id: 3, name: '王强' }
      ],
      warnings: []
    }
  },
  // 项目花费（2026-10-04 真源切换）：与真机 payload 同构 ——
  // 花费 = 消耗/执行明细聚合（Σ 数量×快照单价），reconciliation 为三方对账块
  // （出入库任务消耗行数 / 花费合计 / 消耗明细合计 / 一致性）。
  cost: {
    stats: [
      { label: '累计花费', value: '¥10,900' },
      { label: '物资消耗', value: '¥9,100' },
      { label: '服务执行', value: '¥1,800' },
      { label: '涉及项目数', value: '2 个' }
    ],
    byProject: [
      { name: '高温硅胶研究', count: 2, material: '¥9,100', service: '¥0', total: '¥9,100', ratio: '83%' },
      { name: 'PP 配方开发', count: 2, material: '¥0', service: '¥1,800', total: '¥1,800', ratio: '17%' }
    ],
    byMember: [
      { name: '张伟', project: '高温硅胶研究', count: 2, material: '¥9,100', service: '¥0', total: '¥9,100' },
      { name: '李娜', project: 'PP 配方开发', count: 1, material: '¥0', service: '¥1,200', total: '¥1,200' },
      { name: '王强', project: 'PP 配方开发', count: 1, material: '¥0', service: '¥600', total: '¥600' }
    ],
    // 对账 = 明细物资行 ↔ 出入库流水任务消耗行「一一对应」（行数 + 金额双核对）
    reconciliation: {
      detailMaterialRows: 4,
      ledgerMaterialRows: 4,
      detailMaterialTotal: '¥9,100',
      ledgerMaterialTotal: '¥9,100',
      consistent: true
    }
  },
  meta: {
    team: '演示团队',
    repositoryCount: 0,
    projectCount: 0,
    canManage: false
  },
  defaultTab: 'inventory'
}

// 资源申请详情（单对象 + items/timeline/approvals/linkedConsumptions/meta）
// ⚠ 演示样本 2026-10-06 从「服务单 SQ-2026-0092」换成「材料单 SQ-2026-0091」——
//   理由：SQ-2026-7783 暴露的正是**材料单不出库**这条链路（申请单未绑库存条目/任务），
//   演示样本必须能展示修复后的效果（绑定条目 + 关联任务 + 关联出入库记录）。
export const applyDetailPayload = {
  application: {
    id: 2,
    no: 'SQ-2026-0091',
    status: 'completed',
    statusLabel: '已完成',
    project: { id: 2, name: '高温硅胶研究', code: '#2' },
    requestor: { id: 1, name: '张伟' },
    groupReviewer: { id: 2, name: '李娜' },
    projectReviewer: { id: 3, name: '张伟' },
    // 关联任务：出库由该任务的原生实验消耗触发（不是审批事件）
    myModule: { id: 203, name: '粘接强度验证' },
    note: 'PP 基料用于混料与注塑样条制备',
    createdAt: '2026-09-09 09:00',
    submittedAt: '2026-09-10 14:05',
    groupApprovedAt: '2026-09-10 16:20',
    projectApprovedAt: '2026-09-11 09:10',
    completedAt: '2026-09-12 10:24'
  },
  items: [
    {
      kind: 'material', kindLabel: '材料', name: 'PP 基料 K8003',
      qty: '20 kg', qtyRaw: 20, unit: 'kg',
      unitPrice: '¥ 350', amount: '¥ 7,000',
      targetRepositoryId: 10, targetRepositoryName: '主原料库',
      receivedRepositoryRowId: 101, receivedRepositoryRowName: 'PP 基料 K8003'
    }
  ],
  timeline: [
    { key: 'created',   at: '2026-09-09 09:00', label: '创建申请', by: { id: 1, name: '张伟' } },
    { key: 'submitted', at: '2026-09-10 14:05', label: '提交审批', by: { id: 1, name: '张伟' } },
    { key: 'group',     at: '2026-09-10 16:20', label: '小组通过', by: { id: 2, name: '李娜' } },
    { key: 'project',   at: '2026-09-11 09:10', label: '项目通过', by: { id: 3, name: '张伟' } },
    { key: 'completed', at: '2026-09-12 10:24', label: '已验收入库', by: null }
  ],
  // 关联出入库 / 消耗记录：按绑定库存条目反查任务消耗流水（material 专属）
  linkedConsumptions: [
    {
      id: 501, name: 'PP 基料 K8003', qty: '20 kg',
      amount: '¥7,000', occurredAt: '2026-09-12 10:24', resultStatus: null
    }
  ],
  approvals: {
    groupRequired: false,
    projectRequired: false,
    canApproveGroup: false,
    canApproveProject: false
  },
  meta: {
    team: '演示团队',
    canEdit: false,
    canSubmit: false,
    canComplete: false,
    isRequestor: false
  },
  notFound: false,
  forbidden: false
}
