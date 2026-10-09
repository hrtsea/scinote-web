<template>
  <div ref="modal" class="modal in" tabindex="-1" role="dialog" style="z-index: 2040; display: block;">
    <div class="modal-dialog" role="document">
      <div class="modal-content">
        <div class="modal-header">
          <button type="button" class="close" data-dismiss="modal" aria-label="Close" @click="onClose">
            <i class="sn-icon sn-icon-close"></i>
          </button>
          <h2 class="modal-title"></h2>
        </div>
        <div class="modal-body">
          <div class="flex items-center justify-center">
            <img src="/images/scinote/core/common/premium_upgrade.svg" class="mb-3">
          </div>
          <template v-if="promoType === 'free'">
            <h2>{{ i18n.t('ai_parser.promo_modal.title_free') }}</h2>
            <p>{{ i18n.t('ai_parser.promo_modal.description_free') }}</p>
          </template>
          <template v-else>
            <h2>{{ i18n.t('ai_parser.promo_modal.title_premium') }}</h2>
            <p>{{ i18n.t('ai_parser.promo_modal.description_premium') }}</p>
          </template>
        </div>
        <div v-if="promoType === 'free'" class="modal-footer">
          <a :href="learnMoreUrl" type="button" class="btn btn-secondary" target="_blank">
            {{ i18n.t('ai_parser.promo_modal.learn_more') }}
          </a>
          <a :href="upgradeUrl" type="button" class="btn btn-primary" target="_blank">
            {{ i18n.t('ai_parser.promo_modal.upgrade') }}
          </a>
        </div>
        <div v-else class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal" @click="onClose">
            {{ i18n.t('general.close') }}
          </button>
          <a :href="learnMoreUrl" class="btn btn-primary" target="_blank">
            {{ i18n.t('ai_parser.promo_modal.learn_more') }}
          </a>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
// 付费墙 / 促销弹窗（对齐官方源码级反抽 §6：PromoAIModal）。
// i18n 经 app.config.globalProperties.i18n 注入（Options API 下 this.i18n 可用）。
export default {
  name: 'PromoAIModal',
  props: {
    promoType: { type: String, required: true }, // 'free' | 其它
    upgradeUrl: { type: String, required: false, default: '' },
    learnMoreUrl: { type: String, required: false, default: '' },
    onClose: { type: Function, required: true }
  }
};
</script>
