import { use, init } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { PieChart, BarChart } from 'echarts/charts';
import {
  TitleComponent,
  TooltipComponent,
  LegendComponent,
  GridComponent
} from 'echarts/components';

use([
  CanvasRenderer,
  PieChart,
  BarChart,
  TitleComponent,
  TooltipComponent,
  LegendComponent,
  GridComponent
]);

// 饼图 option：复制核心 charts.js 的饼图形状，数据由 AJAX 注入。
// 环形中心显示任务总数（对齐官方 UI：Tasks / 73），标签由 partial 本地化注入。
function buildPieOption(data, totalLabel) {
  const total = data.reduce((sum, s) => sum + (Number(s.count) || 0), 0);
  const byName = {};
  data.forEach((s) => { byName[s.name] = s; });
  return {
    title: {
      text: String(total),
      subtext: totalLabel,
      left: 'center',
      top: '40%',
      textAlign: 'center',
      textStyle: { fontSize: 24, fontWeight: 600 },
      subtextStyle: { fontSize: 12, fontWeight: 400 }
    },
    tooltip: { trigger: 'item', formatter: '{d}%' },
    // 右侧图例榜（待补 F）：名称 + 计数，对齐官方 UI 的图例榜。
    legend: {
      type: 'scroll',
      orient: 'vertical',
      right: 8,
      top: 'middle',
      itemWidth: 10,
      itemHeight: 10,
      textStyle: { fontSize: 12 },
      formatter: (name) => {
        const item = byName[name];
        return item ? `${name}  ${item.count}` : name;
      }
    },
    series: [
      {
        type: 'pie',
        label: { show: false, position: 'center' },
        labelLine: { show: false },
        radius: ['40%', '70%'],
        itemStyle: { borderRadius: 10, borderColor: '#fff', borderWidth: 2 },
        data: data.map((s) => ({
          value: s.count,
          name: s.name,
          itemStyle: { color: s.color },
          drilldown: 'status:' + s.id
        }))
      }
    ]
  };
}

// 堆叠柱图 option：复制核心 charts.js 的 barOptions 形状。
// 后端 workload 返回扁平行 [{user_id,user_name,status_id,status_name,status_color,count}]，
// 此处 pivot 成 echarts 堆叠柱图结构（每个状态一个 series，按用户分组堆叠）。
function buildBarOption(data) {
  const users = [];
  const statusById = new Map();
  const cell = new Map(); // `${userId}:${statusId}` -> count

  data.forEach((row) => {
    if (!users.some((u) => u.id === row.user_id)) {
      users.push({ id: row.user_id, name: row.user_name });
    }
    if (!statusById.has(row.status_id)) {
      statusById.set(row.status_id, { id: row.status_id, name: row.status_name, color: row.status_color });
    }
    cell.set(`${row.user_id}:${row.status_id}`, row.count);
  });

  users.sort((a, b) => a.name.localeCompare(b.name));
  const statuses = [...statusById.entries()].sort((a, b) => a[0] - b[0]).map((e) => e[1]);
  const userNames = users.map((u) => u.name);

  const series = statuses.map((s) => ({
    name: s.name,
    type: 'bar',
    stack: 'status',
    color: s.color,
    emphasis: { focus: 'series' },
    data: users.map((u) => ({
      value: cell.get(`${u.id}:${s.id}`) || 0,
      drilldown: 'workload:' + u.id + ':' + s.id
    }))
  }));

  return {
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
    xAxis: [{
      type: 'category',
      axisLabel: { hideOverlap: false, interval: 0, overflow: 'truncate', width: 80 },
      data: userNames
    }],
    yAxis: [{ type: 'value' }],
    series
  };
}

// 非图表挂载点（如瓶颈检测卡片）：把聚合返回的计数填到对应 data-count 子元素。
// 全部计数为 0 时显示 [data-empty-state] 空状态（官方 UI：Well done. ...）。
function fillCounts(el, data) {
  let allZero = Object.keys(data).length > 0;
  el.querySelectorAll('[data-count]').forEach((node) => {
    const key = node.getAttribute('data-count');
    const value = data[key];
    node.textContent = (value == null) ? '–' : String(value);
    if (Number(value) > 0) allZero = false;
  });

  const empty = el.querySelector('[data-empty-state]');
  if (empty) empty.hidden = !allZero;
}

// 负载柱图：标题右侧显示"N options selected"（按聚合结果中的 distinct 用户数）。
function fillUserCount(el, data) {
  const widget = el.closest('.project-insights-widget');
  const node = widget && widget.querySelector('[data-user-count-template]');
  if (!node) return;
  const count = new Set(data.map((row) => row.user_id)).size;
  node.textContent = node.getAttribute('data-user-count-template').replace('%{count}', String(count));
}

// 部分聚合端点（workload / tasks_for）在结果为空时会被 ActiveModelSerializers 包裹为
// {"data":[]}；非空数组与计数 Hash（status_overview / bottlenecks / due_dates）原样返回。
// 仅当载荷为 { data: [...] } 形式时解包，避免前端按数组消费时空指针。
function normalizeInsightsData(payload) {
  if (payload && !Array.isArray(payload) && Array.isArray(payload.data)) {
    return payload.data;
  }
  return payload;
}

// D 可交互成员多选：依负载数据填充成员勾选框（默认全选）；取消勾选即按所选成员重绘柱图。
// 计数列 "N options selected" 实时反映勾选数；柱图经 setOption 重绘（复用后端 member_ids 过滤）。
function renderMemberFilter(widget, el, payload) {
  const container = widget.querySelector('[data-member-filter]');
  const items = container && container.querySelector('[data-member-filter-items]');
  if (!items) return;

  const seen = new Set();
  const users = [];
  payload.forEach((row) => {
    if (!seen.has(row.user_id)) {
      seen.add(row.user_id);
      users.push({ id: String(row.user_id), name: row.user_name });
    }
  });
  users.sort((a, b) => a.name.localeCompare(b.name));

  items.innerHTML = '';
  users.forEach((u) => {
    const label = document.createElement('label');
    label.className = 'member-filter-item';
    const cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = true;
    cb.setAttribute('data-member-id', u.id);
    label.appendChild(cb);
    label.appendChild(document.createTextNode(' ' + u.name));
    items.appendChild(label);
  });
  if (container.hidden) container.hidden = false;

  items.addEventListener('change', () => {
    const checked = [...items.querySelectorAll('input[data-member-id]:checked')]
      .map((c) => c.getAttribute('data-member-id'));
    const tpl = widget.querySelector('[data-user-count-template]');
    if (tpl) {
      tpl.textContent = tpl.getAttribute('data-user-count-template').replace('%{count}', String(checked.length));
    }
    refetchWorkload(el, checked);
  });
}

// 按所选成员重取负载数据并仅重绘柱图（不重建图表实例）。
function refetchWorkload(el, memberIds) {
  const base = el.getAttribute('data-ajax-url');
  const url = memberIds.length
    ? `${base}&member_ids[]=${memberIds.map(encodeURIComponent).join('&member_ids[]=')}`
    : base;
  fetch(url, { headers: { Accept: 'application/json' } })
    .then((response) => response.json())
    .then((data) => {
      const arr = normalizeInsightsData(data);
      const chart = echarts.getInstanceByDom(el);
      if (chart) chart.setOption(buildBarOption(arr));
      fillUserCount(el, arr);
    });
}

// 下钻联动（P8）：把 data-drilldown 值翻译为 current_tasks 过滤 URL。
// drilldown 约定：
//   status:<status_id>
//   workload:<user_id>:<status_id>
//   bottlenecks:<bucket>      bucket ∈ seven|fourteen|thirty_plus
//   due_dates:<bucket>        bucket ∈ overdue|today|tomorrow|this_week|next_week
function buildDrilldownUrl(base, drilldown) {
  const parts = (drilldown || '').split(':');
  const kind = parts[0];
  const rest = parts.slice(1);
  const params = new URLSearchParams();
  if (kind === 'status' && rest[0]) {
    params.set('statuses[]', rest[0]);
  } else if (kind === 'workload' && rest.length >= 2) {
    params.set('assigned_user_id', rest[0]);
    params.set('statuses[]', rest[1]);
  } else if (kind === 'bottlenecks' && rest[0]) {
    params.set('stale_bucket', rest[0]);
  } else if (kind === 'due_dates' && rest[0]) {
    params.set('due_bucket', rest[0]);
  }
  const q = params.toString();
  return q ? base + '?' + q : base;
}

// 图表下钻（状态饼图/负载柱图）：点击扇区/柱跳转。
function attachChartDrilldown(chart, el) {
  const base = el.getAttribute('data-drilldown-base');
  if (!base) return;
  chart.on('click', (params) => {
    if (params.data && params.data.drilldown) {
      window.location.href = buildDrilldownUrl(base, params.data.drilldown);
    }
  });
}

// 卡片下钻（瓶颈/截止日期）：点击带 data-drilldown 的卡片跳转。
// 注册在 turbolinks:load 之外，避免每次导航重复绑定。
document.addEventListener('click', (e) => {
  const card = e.target.closest('[data-drilldown]');
  if (!card) return;
  if (card.hasAttribute('data-bucket')) return; // 档内任务列表交由下方处理器接管，不跳转
  const base = card.closest('[data-drilldown-base]');
  if (!base) return;
  window.location.href = buildDrilldownUrl(base.dataset.drilldownBase, card.dataset.drilldown);
});

// 档内任务列表（待补 G）：点击带 data-bucket 的卡片，按档拉取任务列表并内联渲染，
// 不再直接跳转；列表底部保留「在任务列表中查看全部」链接（复用下钻 URL）。
document.addEventListener('click', (e) => {
  const card = e.target.closest('[data-bucket]');
  if (!card) return;
  const widget = card.closest('.project-insights-widget');
  const base = card.closest('[data-drilldown-base]');
  const listUrl = base && base.getAttribute('data-list-url');
  if (!widget || !listUrl) return;

  const drilldown = card.getAttribute('data-drilldown');
  const bucket = drilldown.split(':')[1];
  const url = listUrl + '&bucket=' + encodeURIComponent(bucket);

  fetch(url, { headers: { Accept: 'application/json' } })
    .then((response) => response.json())
    .then((data) => renderBucketList(widget, card, data,
      buildDrilldownUrl(base.dataset.drilldownBase, drilldown)));
});

// 关闭档内任务列表
document.addEventListener('click', (e) => {
  if (e.target.closest('[data-bucket-list-close]')) {
    const panel = e.target.closest('[data-bucket-task-list]');
    if (panel) panel.hidden = true;
  }
});

// 把按档任务列表渲染进 widget 内的 [data-bucket-task-list] 面板。
// 任务名/状态色/日期均经 DOM 节点写入（textContent / style），避免 XSS。
function renderBucketList(widget, card, data, allUrl) {
  const panel = widget.querySelector('[data-bucket-task-list]');
  if (!panel) return;
  const items = panel.querySelector('[data-bucket-list-items]');
  const title = panel.querySelector('[data-bucket-list-title]');
  const all = panel.querySelector('[data-bucket-list-all]');
  const label = card.querySelector('.bottleneck-label, .due-date-label');
  const list = normalizeInsightsData(data);

  title.textContent = label ? label.textContent.trim() : '';
  items.innerHTML = '';

  if (!list.length) {
    const li = document.createElement('li');
    li.className = 'bucket-task-list-empty';
    li.textContent = panel.getAttribute('data-no-tasks') || 'No tasks in this bucket.';
    items.appendChild(li);
  } else {
    list.forEach((task) => {
      const li = document.createElement('li');
      li.className = 'bucket-task-list-item';

      const dot = document.createElement('span');
      dot.className = 'bucket-task-dot';
      dot.style.background = task.status_color || '#999';

      const name = document.createElement('span');
      name.className = 'bucket-task-name';
      name.textContent = task.name;

      const date = document.createElement('small');
      date.className = 'bucket-task-date';
      date.textContent = task.date || '';

      li.appendChild(dot);
      li.appendChild(name);
      li.appendChild(date);
      items.appendChild(li);
    });
  }

  all.href = allUrl;
  all.hidden = false;
  panel.hidden = false;
}

document.addEventListener('turbolinks:load', () => {
  document.querySelectorAll('[data-ajax-url]').forEach((el) => {
    const url = el.getAttribute('data-ajax-url');
    if (!url) return;

    fetch(url, { headers: { Accept: 'application/json' } })
      .then((response) => response.json())
      .then((payload) => {
        // 'pie' | 'bar' 走 echarts；其余（如瓶颈卡片）填计数。
        const data = normalizeInsightsData(payload);
        const kind = el.getAttribute('data-insights-chart');
        if (kind === 'pie') {
          const chart = init(el);
          chart.setOption(buildPieOption(data, el.getAttribute('data-total-label')));
          attachChartDrilldown(chart, el);
        } else if (kind === 'bar') {
          const chart = init(el);
          chart.setOption(buildBarOption(data));
          attachChartDrilldown(chart, el);
          fillUserCount(el, data);
          renderMemberFilter(el.closest('.project-insights-widget'), el, data);
        } else {
          fillCounts(el, data);
        }
      });
  });
});
