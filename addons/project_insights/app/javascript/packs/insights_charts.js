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
function buildPieOption(data) {
  return {
    tooltip: { trigger: 'item', formatter: '{d}%' },
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
function fillCounts(el, data) {
  el.querySelectorAll('[data-count]').forEach((node) => {
    const key = node.getAttribute('data-count');
    const value = data[key];
    node.textContent = (value == null) ? '–' : String(value);
  });
}

// 下钻联动（P8）：把 data-drilldown 值翻译为 current_tasks 过滤 URL。
// drilldown 约定：
//   status:<status_id>
//   workload:<user_id>:<status_id>
//   bottlenecks:<bucket>      bucket ∈ seven|fourteen|thirty_plus
//   due_dates:<bucket>        bucket ∈ overdue|due_today|due_this_week|upcoming
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
  const base = card.closest('[data-drilldown-base]');
  if (!base) return;
  window.location.href = buildDrilldownUrl(base.dataset.drilldownBase, card.dataset.drilldown);
});

document.addEventListener('turbolinks:load', () => {
  document.querySelectorAll('[data-ajax-url]').forEach((el) => {
    const url = el.getAttribute('data-ajax-url');
    if (!url) return;

    fetch(url, { headers: { Accept: 'application/json' } })
      .then((response) => response.json())
      .then((payload) => {
        // 'pie' | 'bar' 走 echarts；其余（如瓶颈卡片）填计数。
        const kind = el.getAttribute('data-insights-chart');
        if (kind === 'pie') {
          const chart = init(el);
          chart.setOption(buildPieOption(payload));
          attachChartDrilldown(chart, el);
        } else if (kind === 'bar') {
          const chart = init(el);
          chart.setOption(buildBarOption(payload));
          attachChartDrilldown(chart, el);
        } else {
          fillCounts(el, payload);
        }
      });
  });
});
