<template>
  <div class="ai-protocol-preview">
    <h3 class="ai-protocol-preview__name">{{ protocolPreview.name }}</h3>
    <p class="ai-protocol-preview__desc">{{ protocolPreview.description }}</p>
    <ul class="ai-protocol-preview__steps">
      <li v-for="(step, idx) in protocolPreview.steps" :key="idx" class="ai-protocol-preview__step">
        <div class="ai-protocol-preview__step-name">{{ step.name }}</div>
        <div class="ai-protocol-preview__step-desc">{{ step.description }}</div>
        <table v-if="step.tables && step.tables.length" class="ai-protocol-preview__table">
          <caption>{{ step.tables[0].name }}</caption>
          <tbody>
            <tr v-for="(row, r) in step.tables[0].data" :key="r">
              <td v-for="(cell, c) in row" :key="c">{{ cell }}</td>
            </tr>
          </tbody>
        </table>
      </li>
    </ul>
  </div>
</template>

<script>
// 协议解析结果预览（对齐官方复用的宿主 ProtocolPreview 组件形态）。
// 输入协议：{ name, description, steps: [{ name, description, tables: [{ name, data: [[..]] }] }] }
export default {
  name: 'ProtocolPreview',
  props: {
    protocolPreview: { type: Object, required: true }
  }
};
</script>

<style scoped>
.ai-protocol-preview__name { font-weight: 600; margin-bottom: 0.25rem; }
.ai-protocol-preview__desc { color: #5b6b7b; margin-bottom: 0.75rem; }
.ai-protocol-preview__step { margin-bottom: 0.75rem; }
.ai-protocol-preview__step-name { font-weight: 600; }
.ai-protocol-preview__table { margin-top: 0.25rem; border-collapse: collapse; font-size: 0.8rem; }
.ai-protocol-preview__table td { border: 1px solid #e0e0e0; padding: 2px 6px; }
</style>
