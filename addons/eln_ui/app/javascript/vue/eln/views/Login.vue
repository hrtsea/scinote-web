<template>
  <!-- 登录页（画布 4:65）：1440×900 双栏 — 左品牌区660 + 右登录卡400 -->
  <div class="login-page">
    <!-- 左：品牌区（渐变 #EDF2FF → #FAFAFA） -->
    <div class="brand-panel">
      <div class="brand-inner">
        <div class="brand-logo"><AppIcon name="flask" :size="20" /></div>
        <h1 class="brand-title">ELN 系统</h1>
        <p class="brand-sub">面向科研院所与企业研发实验室的实验过程数字化管理平台</p>
        <ul class="brand-points">
          <li><AppIcon name="check" :size="16" />项目 — 实验 — 任务三级领域模型，对齐 SciNote 原生结构</li>
          <li><AppIcon name="check" :size="16" />实验记录全程留痕，历史可追溯、角色可审计</li>
          <li><AppIcon name="check" :size="16" />实验设计（DOE）与项目指标一体化联动</li>
        </ul>
        <p class="brand-foot">领域模型对齐 SciNote V1.8</p>
      </div>
    </div>

    <!-- 右：登录卡片（400 宽 白底 圆角14 阴影） -->
    <div class="auth-panel">
      <div class="auth-card">
        <h2 class="auth-title">登录</h2>
        <p class="auth-sub">请使用单位统一身份账号登录</p>

        <!-- 部署形态切换（#F4F4F5 圆角10） -->
        <div class="deploy-switch">
          <button
            v-for="d in deploys"
            :key="d"
            class="deploy-item"
            :class="{ on: deploy === d }"
            @click="deploy = d"
          >
            {{ d }}
          </button>
        </div>
        <p v-if="deploy === '云版'" class="deploy-tip">
          <AppIcon name="shield" :size="14" />云服务由单位统一开通，数据加密存储于云端。
        </p>

        <div class="field">
          <label class="field-label">账号</label>
          <input v-model="account" class="field-input" placeholder="leader@demo" />
        </div>
        <div class="field">
          <label class="field-label">密码</label>
          <input v-model="password" type="password" class="field-input" placeholder="••••••••••" />
        </div>

        <!-- 失败口径 -->
        <p v-if="error" class="auth-error">账号或密码不正确，请重试（连续失败将锁定 10 分钟）</p>

        <button class="login-btn" @click="doLogin">登录</button>

        <div class="quick-title">演示账号快捷登录</div>
        <div class="quick-grid">
          <button
            v-for="q in quickRoles"
            :key="q.label"
            class="quick-btn"
            @click="quickLogin(q.label)"
          >
            {{ q.label }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue/dist/vue.esm-bundler.js'
import { useRouter } from 'vue-router'
import AppIcon from '../components/AppIcon.vue'

const router = useRouter()

const deploys = ['云版', '私有化一体机']
const deploy = ref('云版')
const account = ref('leader@demo')
const password = ref('demo123456')
const error = ref(false)

const quickRoles = [
  { label: '项目负责人' },
  { label: '小组组长' },
  { label: '组员' },
  { label: '单位管理员' }
]

function doLogin() {
  // 演示环境：非空即通过，空则展示失败口径
  if (!account.value || !password.value) {
    error.value = true
    return
  }
  error.value = false
  router.push('/eln_workbench')
}

function quickLogin() {
  error.value = false
  router.push('/eln_workbench')
}
</script>

<style scoped>
.login-page {
  display: flex;
  height: 100vh;
  background: var(--color-page-bg);
}

/* ---------- 品牌区 ---------- */
/* ---------- 品牌区（画布 4:73：width 660 / padding 64 / vertical gap 18） ----------
   画布 4:77 是一个 1px 宽、height:fill_container 的占位块，作用是把「要点区 + 页脚」推到底部；
   HTML 用 .brand-points 的 margin-top:auto 等效实现（4:75/4:76 均为 fill_container → 文字撑满 532 宽）。 */
.brand-panel {
  width: 660px;
  flex-shrink: 0;
  background: linear-gradient(135deg, #EDF2FF 0%, var(--color-page-bg) 100%);
  display: flex;
  padding: 64px;
}
.brand-inner {
  width: 100%;
  display: flex;
  flex-direction: column;
}
.brand-logo {
  width: 40px;
  height: 40px;
  border-radius: 10px;
  background: var(--color-primary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 20px;
}
.brand-title {
  margin: 0;
  font-size: 40px;
  font-weight: 700;
  color: var(--color-text);
  line-height: 1.15;
}
.brand-sub {
  margin: 10px 0 28px;
  font-size: 16px;
  color: var(--color-subtle-text);
}
.brand-points {
  list-style: none;
  margin: auto 0 0; /* 等效画布 4:77 的 fill 占位块：要点区下沉至底部 */
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.brand-points li {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 14px;
  color: var(--color-text-menu);
}
.brand-points svg {
  color: var(--color-primary);
  flex-shrink: 0;
}
.brand-foot {
  margin-top: 40px;
  font-size: 12px;
  color: var(--color-placeholder);
}

/* ---------- 登录卡（画布 4:88 / 4:89） ----------
   4:88 外层 padding 48 + CENTER/CENTER；4:89 卡 width 400 / padding 32 / vertical gap 14 / r14，
   **无描边**（strokes:[]），阴影为双层 DROP_SHADOW（0,18,40,-12,a.10）+（0,6,14,-4,a.08）。 */
.auth-panel {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 48px;
}
.auth-card {
  width: 400px;
  background: var(--color-card);
  border-radius: 14px;
  box-shadow: 0 18px 40px -12px rgba(13, 13, 26, 0.1), 0 6px 14px -4px rgba(13, 13, 26, 0.08);
  padding: 32px;
  display: flex;
  flex-direction: column;
  gap: 14px; /* 画布 4:89：所有子项统一 gap14（下方各元素不再用 margin 控制间距） */
}
.auth-title {
  margin: 0;
  font-size: 22px;
  font-weight: 600;
  color: var(--color-text);
}
.auth-sub {
  margin: 0;
  font-size: 13px;
  color: var(--color-text-secondary);
}
.deploy-switch {
  display: flex;
  background: var(--color-fill-soft);
  border-radius: 10px;
  padding: 4px;
  gap: 4px;
}
.deploy-item {
  flex: 1;
  height: 32px; /* 画布 4:92 h40 / padding4 → 子项 40-8 = 32 */
  border: none;
  border-radius: 8px;
  background: transparent;
  font-size: 13px;
  color: var(--color-text-secondary);
  transition: all 0.15s ease;
}
.deploy-item.on {
  background: var(--color-card);
  color: var(--color-text);
  font-weight: 500;
}
.deploy-tip {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 0;
  font-size: 12px;
  color: var(--color-text-secondary);
}
.deploy-tip svg {
  color: var(--color-primary);
  flex-shrink: 0;
}
.field {
  display: flex;
  flex-direction: column;
  gap: 14px; /* 画布 4:98 → 4:99：label 与输入框同为卡片直属子项，间距即卡 gap14 */
}
.field-label {
  font-size: 13px;
  font-weight: 500;
  color: var(--color-text);
}
.field-input {
  height: 42px; /* 画布 4:99 / 4:102 h42 */
  padding: 0 12px;
  border: 1px solid var(--color-border-strong); /* 画布 stroke #D4D4D8 */
  border-radius: 8px;
  font-size: 13px;
  font-family: inherit;
  color: var(--color-text);
  background: var(--color-card);
  outline: none;
}
.field-input::placeholder {
  color: var(--color-placeholder);
}
.field-input:focus {
  border-color: var(--color-primary);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
}
.auth-error {
  margin: 0;
  font-size: 12px;
  color: var(--color-danger);
}
.login-btn {
  width: 100%;
  height: 44px; /* 画布 4:104 h44 */
  border: none;
  border-radius: var(--radius-button);
  background: var(--color-primary);
  color: #fff;
  font-size: 14px;
  font-weight: 500;
  transition: background 0.15s ease;
}
.login-btn:hover {
  background: var(--color-primary-hover);
}
.quick-title {
  font-size: 12px;
  color: var(--color-placeholder);
  text-align: center;
}
.quick-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  justify-content: center;
}
.quick-btn {
  width: 164px;
  height: 36px;
  background: var(--color-card);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  font-size: 13px;
  color: var(--color-text-menu);
  transition: all 0.15s ease;
}
.quick-btn:hover {
  border-color: var(--color-primary);
  color: var(--color-primary);
  background: var(--color-active-bg);
}
</style>
