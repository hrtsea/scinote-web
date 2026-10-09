<template>
  <div ref="modal" class="modal in" tabindex="-1" role="dialog" style="z-index: 2050; display: block;">
    <div class="modal-dialog" role="document">
      <div class="modal-content">
        <div class="modal-header">
          <button type="button" class="close" data-dismiss="modal" aria-label="Close" @click="onClose">
            <i class="sn-icon sn-icon-close"></i>
          </button>
          <h2 class="modal-title">{{ i18n.t('ai_parser.confirmation_modal.title') }}</h2>
        </div>
        <div class="modal-body">
          <p>{{ i18n.t('ai_parser.confirmation_modal.description') }}</p>
          <p v-html="i18n.t('ai_parser.confirmation_modal.description_load_html')"></p>
          <div class="flex gap-2 mb-2">
            <div class="sci-radio-container shrink-0 mt-0.5">
              <input type="radio" v-model="loadMode" name="load_option" value="merge" class="sci-radio" checked>
            </div>
            <label class="sci-label !my-0" v-html="i18n.t('ai_parser.confirmation_modal.option_merge_html')"></label>
          </div>
          <div class="flex gap-2 mb-6">
            <div class="sci-radio-container shrink-0 mt-0.5">
              <input type="radio" v-model="loadMode" name="load_option" value="replace" class="sci-radio">
            </div>
            <label class="sci-label !my-0" v-html="i18n.t('ai_parser.confirmation_modal.option_replace_html')"></label>
          </div>
          <p class="font-bold" v-html="i18n.t('ai_parser.confirmation_modal.confirmation_description_html')"></p>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" @click="onClose">{{ i18n.t('general.cancel') }}</button>
          <button type="button" class="btn btn-danger" :disabled="uploading" @click="importProtocol">
            {{ i18n.t('ai_parser.confirmation_modal.load') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import * as api from './api.js';

// 导入确认：merge / replace（对齐官方源码级反抽 §6：ConfirmAIUploadModal）。
export default {
  name: 'ConfirmAIUploadModal',
  props: {
    parsedProtocolId: { type: [String, Number], required: true },
    myModuleId: { required: true },
    onClose: { type: Function, required: true }
  },
  data() {
    return { loadMode: 'merge', uploading: false };
  },
  methods: {
    async importProtocol() {
      if (this.uploading) return;
      this.uploading = true;
      try {
        await api.importProtocol(this.parsedProtocolId, {
          myModuleId: this.myModuleId,
          loadMode: this.loadMode
        });
        if (this.myModuleId) {
          window.location.reload();
        } else if (window.protocolsTable && window.protocolsTable.$refs && window.protocolsTable.$refs.table) {
          window.protocolsTable.$refs.table.updateTable();
          this.onClose();
        } else {
          window.location.reload();
        }
      } catch (e) {
        this.uploading = false;
        if (window.HelperModule) {
          window.HelperModule.flashAlertMsg(this.i18n.t('general.error'), 'danger');
        }
      }
    }
  }
};
</script>
