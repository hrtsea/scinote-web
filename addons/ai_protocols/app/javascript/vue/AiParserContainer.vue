<template>
  <div>
    <button id="importWithAI" class="tw-hidden" ref="openModalButton"></button>
    <AIImportModal
      v-if="showModal && aiParserEnabled === 'true'"
      :onClose="closeModal"
      :fileLimitMb="fileLimitMb"
    />
    <PromoAIModal
      v-else-if="showModal"
      :onClose="closeModal"
      :promoType="aiParserPromo"
      :upgradeUrl="upgradeUrl"
      :learnMoreUrl="learnMoreUrl"
    />
  </div>
</template>

<script>
import AIImportModal from './AIImportModal.vue';
import PromoAIModal from './PromoAIModal.vue';

// 根组件 AiParserContainer（对齐官方源码级反抽 §4）：
// hidden #importWithAI 触发器 + showModal 单状态下「导入弹窗 / 付费墙」二选一。
export default {
  name: 'AiParserContainer',
  components: { AIImportModal, PromoAIModal },
  props: {
    fileLimitMb: { required: true },
    aiParserPromo: { required: true },
    aiParserEnabled: { required: true }, // 字符串 "true"/"false"
    upgradeUrl: { required: false, default: '' },
    learnMoreUrl: { required: false, default: '' }
  },
  data() {
    return { showModal: false };
  },
  mounted() {
    // 宿主入口（protocolOptions.vue / protocols/table.vue）点击 #importWithAI 触发。
    this.$refs.openModalButton.addEventListener('click', () => { this.showModal = true; });
  },
  methods: {
    closeModal() { this.showModal = false; }
  }
};
</script>
