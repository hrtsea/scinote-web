<template>
  <!-- 个人中心（画布 79:1456 / PRD §7.12）：左栏个人摘要 + 导航，右栏四卡 -->
  <div class="profile-page">
    <!-- 面包屑 -->
    <div class="breadcrumb">
      <router-link to="/eln_workbench" class="crumb-link">工作台</router-link>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">个人中心</span>
    </div>

    <!-- 页头 -->
    <div class="pf-head">
      <PageHeader
        title="个人中心"
        subtitle="个人信息 · 修改密码 · 我的操作日志 · 云版额外提供本人 AI 调用消耗记录（REQ-PROFILE）"
        show-navigator
        @toggle-navigator="ui.navigatorOpen ? closeNavigator() : openNavigator()"
      />
      <div class="pf-head-note">全部登录用户可访问（SCN-PROFILE-1） · 入口：顶栏头像下拉（DEC-013）</div>
    </div>

    <!-- 主区：左摘要导航 260 + 右四卡 -->
    <div class="pf-main">
      <!-- 左栏 -->
      <aside class="pf-side">
        <div class="pf-summary eln-card">
          <div class="pf-avatar">张</div>
          <div class="pf-name">张伟</div>
          <div class="pf-mail">zhangwei@lab.cn</div>
          <div class="pf-chips">
            <span class="pf-chip pf-chip-blue">项目负责人</span>
            <span class="pf-chip">高分子材料组</span>
          </div>
          <div class="pf-last">最后登录 2026-09-29 21:40</div>
        </div>
        <nav class="pf-nav eln-card">
          <button
            v-for="n in navs"
            :key="n.key"
            class="pf-nav-item"
            :class="{ active: activeNav === n.key }"
            @click="scrollTo(n.key)"
          >{{ n.label }}</button>
        </nav>
      </aside>

      <!-- 右栏 -->
      <div class="pf-content">
        <!-- 卡 1：个人信息 -->
        <section id="sec-info" class="eln-card pf-card">
          <div class="pf-card-head">
            <div class="pf-card-title">个人信息</div>
            <div class="pf-card-note">可编辑项保存后自动生效（SCN-PROFILE-2）；用户名与所属团队由系统维护，不可改</div>
          </div>
          <div class="pf-grid">
            <div class="pf-field">
              <label>用户名（只读）</label>
              <input class="pf-input readonly" value="zhangwei" readonly />
            </div>
            <div class="pf-field">
              <label>姓名</label>
              <input class="pf-input" v-model="form.name" />
            </div>
            <div class="pf-field">
              <label>邮箱</label>
              <input class="pf-input" v-model="form.email" />
            </div>
            <div class="pf-field">
              <label>手机号</label>
              <input class="pf-input" v-model="form.phone" />
            </div>
            <div class="pf-field">
              <label>所属团队（只读）</label>
              <input class="pf-input readonly" value="高分子材料组" readonly />
            </div>
            <div class="pf-field">
              <label>业务角色（只读）</label>
              <input class="pf-input readonly" value="项目负责人（REQ-ROLE-MAP · DEC-007）" readonly />
            </div>
          </div>
          <div class="pf-card-foot">
            <span class="pf-foot-hint">修改后其他设备会话需重新登录</span>
            <div class="pf-foot-btns">
              <button class="eln-btn-ghost">取消</button>
              <button class="eln-btn-primary">保存修改</button>
            </div>
          </div>
        </section>

        <!-- 卡 2：修改密码 -->
        <section id="sec-pass" class="eln-card pf-card">
          <div class="pf-card-head">
            <div class="pf-card-title">修改密码</div>
            <div class="pf-card-note">新密码须 ≥ 8 位并含字母与数字（SCN-PROFILE-2）</div>
          </div>
          <div class="pf-pass">
            <div class="pf-field">
              <label>当前密码</label>
              <input type="password" class="pf-input" placeholder="请输入当前密码" v-model="pass.current" />
            </div>
            <div class="pf-field">
              <label>新密码</label>
              <input type="password" class="pf-input" placeholder="请输入新密码（≥ 8 位，含字母与数字）" v-model="pass.next" />
            </div>
            <div class="pf-field">
              <label>确认新密码</label>
              <input type="password" class="pf-input" placeholder="请再次输入新密码" v-model="pass.confirm" />
            </div>
          </div>
          <div class="pf-card-foot">
            <span class="pf-foot-hint">修改后其他设备会话 Token 失效，需重新登录</span>
            <button class="eln-btn-primary">确认修改</button>
          </div>
        </section>

        <!-- 卡 3：我的操作日志 -->
        <section id="sec-log" class="eln-card pf-card">
          <div class="pf-card-head">
            <div class="pf-card-title">我的操作日志</div>
            <div class="pf-card-note">仅显示本人操作记录（SCN-PROFILE-3） · 全量审计见系统管理 / 操作日志</div>
          </div>
          <table class="eln-table">
            <thead>
              <tr>
                <th class="eln-th">时间</th>
                <th class="eln-th">操作动作</th>
                <th class="eln-th">对象</th>
                <th class="eln-th">来源 IP</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(r, i) in logs" :key="i">
                <td class="eln-td">{{ r.time }}</td>
                <td class="eln-td">{{ r.action }}</td>
                <td class="eln-td">{{ r.target }}</td>
                <td class="eln-td">{{ r.ip }}</td>
              </tr>
            </tbody>
          </table>
          <div class="pf-footnote">共 4 条 · 仅展示本人操作，不可查看他人记录（SCN-PROFILE-3）；数据保留受使用锁（REQ-NFR 审计留痕）。</div>
        </section>

        <!-- 卡 4：本人 AI 消耗记录（云版） -->
        <section id="sec-ai" class="eln-card pf-card">
          <div class="pf-card-head">
            <div class="pf-card-title">本人 AI 消耗记录（云版）</div>
            <div class="pf-card-note">云版专有（SCN-PROFILE-4） · 私有化部署不消耗 Token，本面板不展示（SCN-AI-5）</div>
          </div>
          <table class="eln-table">
            <thead>
              <tr>
                <th class="eln-th">时间</th>
                <th class="eln-th">功能入口</th>
                <th class="eln-th">模型</th>
                <th class="eln-th">Tokens</th>
                <th class="eln-th">费用（¥）</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(r, i) in aiRecords" :key="i">
                <td class="eln-td">{{ r.time }}</td>
                <td class="eln-td">{{ r.entry }}</td>
                <td class="eln-td">{{ r.model }}</td>
                <td class="eln-td">{{ r.tokens }}</td>
                <td class="eln-td">{{ r.fee }}</td>
              </tr>
              <tr>
                <td class="eln-td pf-total">合计</td>
                <td class="eln-td pf-total">3 次调用（本人）</td>
                <td class="eln-td pf-total">—</td>
                <td class="eln-td pf-total pf-blue">19,500</td>
                <td class="eln-td pf-total pf-blue">1.64</td>
              </tr>
            </tbody>
          </table>
          <div class="pf-footnote">
            仅本人可见（SCN-PROFILE-4）；云版每次 AI 调用消耗 Token 并记录日志（SCN-AI-4），受账户余额限制（SCN-AI-6 / DEC-005）；
            单位级 Token 汇总报表见报表中心。
          </div>
        </section>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue/dist/vue.esm-bundler.js'
import PageHeader from '../components/PageHeader.vue'
import { ui, openNavigator, closeNavigator } from '../store/ui'

const navs = [
  { key: 'sec-info', label: '个人信息' },
  { key: 'sec-pass', label: '修改密码' },
  { key: 'sec-log', label: '我的操作日志' },
  { key: 'sec-ai', label: 'AI 消耗记录（云版）' }
]
const activeNav = ref('sec-info')

const form = ref({
  name: '张伟',
  email: 'zhangwei@lab.cn',
  phone: '138****6621'
})

const pass = ref({ current: '', next: '', confirm: '' })

const logs = [
  { time: '2026-09-29 21:40', action: '导出项目花费报表（Excel）', target: '报表中心 · 近 30 天', ip: '10.20.3.18' },
  { time: '2026-09-29 20:12', action: '终审通过资源申请', target: '资源申请单 RA-2026-018', ip: '10.20.3.18' },
  { time: '2026-09-29 18:05', action: '更新实验设计 DOE 方案', target: 'EXP-021 · 实验设计与配方优化', ip: '10.20.3.18' },
  { time: '2026-09-29 16:33', action: '消耗物资出库（任务消耗）', target: 'TSK-118 · 滑石粉 TYT-777A 8 kg', ip: '10.20.3.18' }
]

const aiRecords = [
  { time: '2026-09-29 18:06', entry: '实验设计 · 解读贝叶斯优化结果', model: 'deepseek-chat', tokens: '8,420', fee: '0.71' },
  { time: '2026-09-29 15:22', entry: '实验记录本 · 生成实验总结', model: 'deepseek-chat', tokens: '6,150', fee: '0.52' },
  { time: '2026-09-28 11:08', entry: '项目指标 · 任务书解析', model: 'deepseek-chat', tokens: '4,930', fee: '0.41' }
]

function scrollTo(id) {
  activeNav.value = id
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}
</script>

<style scoped>
.profile-page {
  padding: 28px;
  display: flex;
  flex-direction: column;
  gap: 16px; /* 画布 79:1459 内容区 gap 16 */
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
.crumb-current {
  color: var(--color-placeholder);
  font-weight: 400;
}
.crumb-sep {
  color: var(--color-placeholder);
}
.pf-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.pf-head-note {
  max-width: 320px;
  font-size: 12px;
  color: var(--color-placeholder); /* 画布 79:1467 权限提示 #A1A1AA */
  text-align: right;
  line-height: 1.6;
  padding-top: 4px;
}

/* 主区两栏 */
.pf-main {
  display: flex;
  align-items: flex-start;
  gap: 20px;
}
.pf-side {
  width: 260px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 16px;
  position: sticky;
  top: 28px;
}
.pf-summary {
  padding: 24px 20px;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
}
.pf-avatar {
  width: 64px;
  height: 64px;
  border-radius: 50%;
  background: var(--color-avatar-bg);
  color: var(--color-avatar-text);
  font-size: 24px;
  font-weight: 600;
  display: flex;
  align-items: center;
  justify-content: center;
}
.pf-name {
  margin-top: 12px;
  font-size: 16px;
  font-weight: 600;
}
.pf-mail {
  margin-top: 2px;
  font-size: 12px;
  color: var(--color-text-secondary);
}
.pf-chips {
  margin-top: 10px;
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
  justify-content: center;
}
.pf-chip {
  font-size: 11px;
  padding: 3px 10px;
  border-radius: var(--radius-chip);
  background: var(--color-fill-soft);
  color: var(--color-text-menu);
}
.pf-chip-blue {
  background: var(--color-active-bg);
  color: var(--color-primary);
}
.pf-last {
  margin-top: 12px;
  font-size: 11px;
  color: var(--color-placeholder);
}

/* 导航 */
.pf-nav {
  padding: 8px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.pf-nav-item {
  height: 38px;
  padding: 0 12px;
  background: none;
  border: none;
  border-radius: var(--radius-small);
  font-size: 13px;
  color: var(--color-text-menu);
  text-align: left;
}
.pf-nav-item:hover {
  background: var(--color-fill-soft);
}
.pf-nav-item.active {
  background: var(--color-active-bg);
  color: var(--color-primary);
  font-weight: 500;
}

/* 右栏四卡 */
.pf-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 16px;
}
/* 卡片（画布 79:1459 区：卡片 padding=0，内缩下沉到卡头 / 表格单元格 / 卡尾） */
.pf-card {
  padding: 0;
  overflow: hidden;
  scroll-margin-top: 28px;
}
/* 卡头（画布 h56 / padding 0 20 / 垂直居中） */
.pf-card-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  height: 56px;
  padding: 0 20px;
  flex-wrap: wrap;
}
.pf-card-title {
  font-size: 14px;
  font-weight: 600;
}
.pf-card-note {
  font-size: 12px;
  color: var(--color-text-secondary);
}

/* 表单 */
.pf-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  padding: 0 20px;
}
.pf-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.pf-field label {
  font-size: 12px;
  color: var(--color-text-secondary);
}
.pf-input {
  height: 38px;
  padding: 0 12px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-button);
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
  background: var(--color-card);
  outline: none;
  transition: border-color 0.15s ease;
}
.pf-input:focus {
  border-color: var(--color-primary);
}
.pf-input.readonly {
  background: var(--color-fill-soft);
  color: var(--color-text-secondary);
}
.pf-pass {
  display: flex;
  flex-direction: column;
  gap: 14px;
  max-width: 460px;
  padding: 0 20px;
}
.pf-card-foot {
  margin-top: 16px;
  padding: 14px 20px 20px;
  border-top: 1px solid var(--color-divider);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}
.pf-foot-hint {
  font-size: 12px;
  color: var(--color-placeholder);
}
.pf-foot-btns {
  display: flex;
  gap: 8px;
}

/* 表格卡 */
.pf-blue {
  color: var(--color-primary);
  font-weight: 600;
}
.pf-total {
  border-top: 1px solid var(--color-border);
  border-bottom: none;
  font-weight: 500;
}
.pf-footnote {
  margin: 12px 20px 14px;
  font-size: 11px;
  line-height: 1.7;
  color: var(--color-placeholder);
  background: var(--color-fill-soft);
  border-radius: var(--radius-small);
  padding: 10px 14px;
}
</style>
