<template>
  <!-- 实验设计聚焦视图（画布 4:70 / 4:641）：面包屑 + 页头 + 优化结果区 + 迭代记录看板 -->
  <div class="design-view">
    <div class="breadcrumb">
      <router-link to="/eln_project_list" class="crumb-link">项目列表</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/projects/PR1025240/eln_project_detail" class="crumb-link">150°C 蒸汽环境金属粘接用高温硅胶研究</router-link>
      <span class="crumb-sep">/</span>
      <router-link to="/experiments/EX1/eln_exp_detail" class="crumb-link">EX1 · 实验设计与配方优化</router-link>
    </div>

    <!-- 页头 4:643 -->
    <div class="design-head">
      <div class="head-text">
        <h1 class="head-title">实验设计与配方优化</h1>
        <p class="head-sub">
          聚焦视图 · 场景 B 已有历史数据（贝叶斯优化）· 配置与计算只在实验级执行，产出任务生成在该实验下（DEC-009）
        </p>
      </div>
      <span class="eln-badge eln-badge-orange">云版 · 消耗 Token 并记录日志</span>
    </div>

    <!-- 优化结果区 4:649：推荐条件行 755 + 收敛趋势卡 380 -->
    <div class="result-row">
      <div class="rec-cards">
        <div
          v-for="r in designRecommendations"
          :key="r.round"
          class="rec-card"
          :class="{ best: r.best }"
        >
          <div class="rec-round">{{ r.round }}</div>
          <div class="rec-cond">{{ r.cond }}</div>
          <div class="rec-predict" :class="{ muted: r.muted }">{{ r.predict }}</div>
        </div>
      </div>

      <!-- 收敛趋势卡 4:663 -->
      <div class="trend-card">
        <div class="trend-title">优化目标收敛趋势</div>
        <!-- 画布 4:1101（frame h190）：轴线 #D4D4D8（4:1102/1103）+ 3 条水平网格 #F1F5F9（4:1104-1106）
             + 曲线 #2563EB（4:1110）+ 8 个数据点（末点绿 11px，4:1118）。
             画布**无「目标线」向量**，故不画虚线；仅第 6/7/8 轮有实测/预测值，按「不补造」只画 3 点。 -->
        <svg class="trend-chart" viewBox="0 0 304 150" preserveAspectRatio="none">
          <line x1="0" y1="20" x2="304" y2="20" stroke="#F1F5F9" stroke-width="1" />
          <line x1="0" y1="75" x2="304" y2="75" stroke="#F1F5F9" stroke-width="1" />
          <line x1="0" y1="130" x2="304" y2="130" stroke="#F1F5F9" stroke-width="1" />
          <line x1="0" y1="0" x2="0" y2="130" stroke="#D4D4D8" stroke-width="1" />
          <line x1="0" y1="130" x2="304" y2="130" stroke="#D4D4D8" stroke-width="1" />
          <!-- 第6轮 7.4 → 第7轮 8.1 → 第8轮 8.4（预测） -->
          <polyline
            points="28,96 152,58 276,44"
            fill="none"
            stroke="#2563EB"
            stroke-width="2.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
          <circle cx="28" cy="96" r="4" fill="#2563EB" />
          <circle cx="152" cy="58" r="4" fill="#2563EB" />
          <circle cx="276" cy="44" r="5.5" fill="#10B981" />
        </svg>
        <!-- X 轴说明（画布 4:1119 原文，单一居中文案） -->
        <div class="trend-labels">
          <span>贝叶斯优化迭代轮次 1 - 8</span>
        </div>
      </div>
    </div>

    <!-- 卡片-迭代记录看板 4:681 -->
    <section class="board-card">
      <div class="board-title">迭代记录看板（数据来源：本实验实验设计模块）</div>
      <div class="it-head">
        <span class="col-round">轮次</span>
        <span class="col-method">优化方法</span>
        <span class="col-inputs">输入变量</span>
        <span class="col-rec">推荐条件</span>
        <span class="col-result">实验结果</span>
      </div>
      <div v-for="it in iterations" :key="it.round" class="it-row">
        <span class="col-round num">{{ it.round }}</span>
        <span class="col-method">{{ it.method }}</span>
        <span class="col-inputs">{{ it.inputs }}</span>
        <span class="col-rec">{{ it.recommend }}</span>
        <span class="col-result" :class="it.resultTone">{{ it.result }}</span>
      </div>
      <p class="board-foot">
        ⓘ 画布 4:681 仅展示两行「第 6 轮 / 第 8 轮」；其余轮次未在画布中给出，故不补造。
      </p>
    </section>
  </div>
</template>

<script setup>
import { designRecommendations, iterations } from '../data/mock'
</script>

<style scoped>
.design-view {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.breadcrumb {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
}
.crumb-link {
  color: var(--color-placeholder);
  text-decoration: none;
}
.crumb-link:hover {
  color: var(--color-primary);
}
.crumb-sep {
  color: var(--color-placeholder);
}

/* 页头 4:643 */
.design-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.head-text {
  display: flex;
  flex-direction: column;
  gap: 6px;
  flex: 1;
  min-width: 0;
}
.head-title {
  margin: 0;
  font-size: 20px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.3;
}
.head-sub {
  margin: 0;
  font-size: 12px;
  color: var(--color-text-secondary);
}

/* 优化结果区 4:649（hug_contents）→ 子卡各按内容高，不强制等高拉伸 */
.result-row {
  display: flex;
  gap: 16px;
  align-items: flex-start;
}
.rec-cards {
  display: flex;
  gap: 12px;
  width: 755px;
  flex-shrink: 0;
}
.rec-card {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 16px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
}
.rec-card.best {
  border-color: #BFDBFE;
}
.rec-round {
  font-size: 11px;
  color: var(--color-text-secondary);
}
.rec-cond {
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text);
  line-height: 1.5;
}
.rec-predict {
  font-size: 12px;
  font-weight: 500;
  color: #10B981;
}
.rec-predict.muted {
  color: var(--color-text-secondary);
}

/* 收敛趋势卡 4:663 */
.trend-card {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 16px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
}
.trend-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text);
}
.trend-chart {
  width: 100%;
  height: 170px;
}
.trend-labels {
  display: flex;
  justify-content: space-between;
  font-size: 11px;
  color: var(--color-placeholder);
}

/* 迭代记录看板 4:681 */
.board-card {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 20px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-card);
}
.board-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text);
}
.it-head,
.it-row {
  display: flex;
  align-items: center;
  gap: 12px;
}
.it-head {
  height: 40px;
  padding: 0 12px;
  background: var(--color-table-header);
  border-radius: var(--radius-table-header);
}
.it-head span {
  font-size: 11px;
  font-weight: 500;
  color: var(--color-text-secondary);
}
.it-row {
  min-height: 46px;
  padding: 12px;
  background: #FAFAFA;
  border-radius: 8px;
}
.col-round {
  width: 70px;
  flex-shrink: 0;
}
.col-method {
  width: 110px;
  flex-shrink: 0;
}
.col-inputs {
  flex: 1;
  min-width: 0;
}
.col-rec {
  width: 230px;
  flex-shrink: 0;
}
.col-result {
  width: 120px;
  flex-shrink: 0;
}
.it-row .col-round {
  font-size: 12px;
  font-weight: 500;
  color: var(--color-text-menu);
}
.it-row .col-method,
.it-row .col-inputs,
.it-row .col-rec {
  font-size: 12px;
  color: var(--color-subtle-text);
}
.it-row .col-result {
  font-size: 12px;
  font-weight: 500;
}
.col-result.done {
  color: #10B981;
}
.col-result.warn {
  color: #F59E0B;
}
.board-foot {
  margin: 0;
  font-size: 11px;
  color: var(--color-placeholder);
}
</style>
