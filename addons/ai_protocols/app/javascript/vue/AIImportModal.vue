<template>
  <div>
    <!-- 处理中遮罩 -->
    <div v-if="uploading" class="fixed flex justify-center top-0 left-0 w-full h-full z-[5000]">
      <div class="z-10">
        <div class="flex items-center gap-3 mt-80 rounded bg-sn-super-light-blue p-3">
          <span class="sci-loader-inline relative z-10"></span>
          <span>{{ i18n.t('ai_parser.modal.processing') }}</span>
        </div>
      </div>
    </div>

    <div ref="modal" class="modal in" tabindex="-1" role="dialog" style="z-index: 2040; display: block;">
      <div class="modal-dialog modal-lg" role="document">
        <!-- 预览态 -->
        <div v-if="protocolValid && protocolPreview" key="preview" class="modal-content">
          <div class="modal-header">
            <button type="button" class="close" data-dismiss="modal" aria-label="Close" @click="onClose">
              <i class="sn-icon sn-icon-close"></i>
            </button>
            <h4 class="modal-title !block truncate">{{ i18n.t('ai_parser.modal.protocol_preview') }}</h4>
          </div>
          <div class="modal-body">
            <p class="text-sm">{{ i18n.t('ai_parser.modal.preview_description') }}</p>
            <ProtocolPreview :protocolPreview="protocolPreview" />
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" :aria-label="'Close'" @click="onClose">
              {{ i18n.t('general.cancel') }}
            </button>
            <button type="button" class="btn btn-primary" @click="importProtocol">
              {{ myModuleId ? i18n.t('ai_parser.modal.create_protocol') : i18n.t('ai_parser.modal.create_template') }}
            </button>
          </div>
        </div>

        <!-- 表单态 -->
        <div v-else key="form" class="modal-content !p-0 grid grid-cols-3">
          <!-- 左栏：5 步引导 -->
          <div class="bg-sn-super-light-grey p-6 mb-1.5">
            <div class="flex justify-start mb-1.5">
              <h3 class="modal-title !text-base">{{ i18n.t('ai_parser.modal.how_to_use_title') }}</h3>
            </div>
            <div class="flex flex-col mt-4">
              <div v-for="(block, i) in informationBlocks" :key="i" class="flex gap-3 mt-2">
                <div v-if="i > 0" class="ml-0.5 left-4 relative w-0"></div>
                <div class="rounded h-8 w-8 flex items-center justify-center bg-white border border-sn-sleepy-grey shrink-0">
                  <i class="text-sn-dark-grey sn-icon" :class="block.icon"></i>
                </div>
                <div class="text-sn-dark-grey text-xs flex flex-col gap-2 mt-2">
                  <h3 class="my-0 !text-xs">{{ block.label }}</h3>
                  <p v-if="block.description">{{ block.description }}</p>
                </div>
              </div>
            </div>
          </div>

          <!-- 右栏：表单 -->
          <div class="col-span-2 p-6 flex flex-col">
            <div class="modal-header !p-0">
              <button type="button" class="close" data-dismiss="modal" aria-label="Close" @click="onClose">
                <i class="sn-icon sn-icon-close"></i>
              </button>
              <h4 class="modal-title !block truncate">{{ i18n.t('ai_parser.modal.title') }}</h4>
            </div>

            <div class="modal-body grow">
              <!-- 配额用尽 -->
              <div v-if="remainingCount !== null && remainingCount <= 0" key="limit" class="text-sn-delete-red">
                <p>{{ i18n.t('ai_parser.modal.limit_reached', { daily_limit: dailyLimit }) }}</p>
              </div>
              <!-- 正常表单 -->
              <div v-else key="form-body">
                <p>{{ i18n.t('ai_parser.modal.description') }}</p>
                <div class="flex items-center gap-2 mb-4">
                  <button type="button"
                          class="btn btn-secondary"
                          :class="{ '!bg-sn-super-light-blue !border-sn-blue': createMode === 'prompt_only' }"
                          @click="createMode = 'prompt_only'">
                    {{ i18n.t('ai_parser.modal.prompt_only') }}
                  </button>
                  <button type="button"
                          class="btn btn-secondary"
                          :class="{ '!bg-sn-super-light-blue !border-sn-blue': createMode === 'file_upload' }"
                          @click="createMode = 'file_upload'">
                    {{ i18n.t('ai_parser.modal.file_upload') }}
                  </button>
                </div>

                <!-- 文件上传 -->
                <div v-if="createMode === 'file_upload'" key="file">
                  <label class="sci-label">{{ i18n.t('ai_parser.modal.file_import') }}</label>
                  <div v-if="file" class="flex items-center justify-between bg-sn-super-light-grey p-2 rounded">
                    <div class="flex items-center gap-2">
                      <i class="sn-icon mr-2" :class="fileFormatIcon"></i>
                      <span>{{ file.name }}</span>
                    </div>
                    <button type="button" class="btn btn-light icon-btn" @click="file = null">
                      <i class="sn-icon sn-icon-close"></i>
                    </button>
                  </div>
                  <DragAndDropUpload
                    v-else
                    class="!h-32"
                    :supportingText="i18n.t('ai_parser.modal.supporting_text')"
                    :supportedFormats="['pdf']"
                    @onFile:dropped="setFile"
                    @onFile:error="handleError"
                  />
                </div>

                <!-- 提示词 -->
                <div class="mt-4">
                  <label class="sci-label">{{ i18n.t('ai_parser.modal.prompt_label') }}</label>
                  <textarea
                    v-model="prompt"
                    class="sci-input w-full"
                    :placeholder="placeholder"
                  ></textarea>
                </div>

                <!-- 错误 / 免责声明 -->
                <div v-if="error" key="err" class="flex flex-row items-center text-sn-delete-red mt-2">
                  <i class="sn-icon sn-icon-alert-warning"></i> {{ error }}
                </div>
                <p v-else class="mt-2 text-xs text-sn-dark-grey">{{ i18n.t('ai_parser.modal.disclaimer') }}</p>
              </div>
            </div>

            <div class="modal-footer">
              <button type="button" class="btn btn-secondary" @click="onClose">{{ i18n.t('general.cancel') }}</button>
              <button type="button" class="btn btn-primary" :disabled="disabled" @click="createProtocol">
                {{ createMode === 'file_upload' ? i18n.t('ai_parser.modal.upload') : i18n.t('ai_parser.modal.generate') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 导入确认（Teleport 到 body） -->
    <Teleport to="body">
      <ConfirmAIUploadModal
        v-if="showConfirmationModal"
        :parsedProtocolId="parsedProtocolId"
        :myModuleId="myModuleId"
        :onClose="closeConfirmation"
      />
    </Teleport>
  </div>
</template>

<script>
import * as api from './api.js';
import DragAndDropUpload from './DragAndDropUpload.vue';
import ConfirmAIUploadModal from './ConfirmAIUploadModal.vue';
import ProtocolPreview from './ProtocolPreview.vue';

// AI 导入弹窗（对齐官方源码级反抽 §5：异步创建 + 3s 轮询 + 导入）。
export default {
  name: 'AIImportModal',
  components: { DragAndDropUpload, ConfirmAIUploadModal, ProtocolPreview },
  props: {
    fileLimitMb: { required: true },
    onClose: { type: Function, required: true }
  },
  data() {
    return {
      file: null,
      error: null,
      prompt: '',
      uploading: false,
      parsedProtocolId: null,
      protocolPreview: null,
      protocolValid: null,
      dailyLimit: null,
      remainingCount: null,
      showConfirmationModal: false,
      createMode: 'prompt_only', // prompt_only | file_upload
      myModuleId: null,
      emptyTask: false
    };
  },
  computed: {
    informationBlocks() {
      return [
        { icon: 'sn-icon-search-options', label: this.i18n.t('ai_parser.modal.information_blocks.select_option.label'), description: this.i18n.t('ai_parser.modal.information_blocks.select_option.description') },
        { icon: 'sn-icon-edit', label: this.i18n.t('ai_parser.modal.information_blocks.write_prompt.label'), description: this.i18n.t('ai_parser.modal.information_blocks.write_prompt.description') },
        { icon: 'sn-icon-ai', label: this.i18n.t('ai_parser.modal.information_blocks.generate.label'), description: this.i18n.t('ai_parser.modal.information_blocks.generate.description') },
        { icon: 'sn-icon-visibility-show', label: this.i18n.t('ai_parser.modal.information_blocks.review.label') },
        { icon: 'sn-icon-new-task', label: this.i18n.t('ai_parser.modal.information_blocks.create_template.label'), description: this.i18n.t('ai_parser.modal.information_blocks.create_template.description') }
      ];
    },
    disabled() {
      return !!this.uploading
        || (this.createMode === 'file_upload' && !this.file)
        || this.prompt.length < 1;
    },
    placeholder() {
      const p1 = this.i18n.t('ai_parser.modal.prompt_placeholder_1');
      const p2 = this.createMode === 'file_upload'
        ? this.i18n.t('ai_parser.modal.prompt_placeholder_2_file')
        : this.i18n.t('ai_parser.modal.prompt_placeholder_2_text');
      return `${p1}\n${p2}`;
    },
    fileFormatIcon() {
      if (!this.file) return null;
      const ext = this.file.name.split('.').pop().toLowerCase();
      return ext === 'pdf' ? 'sn-icon-file-pdf' : ext === 'docx' ? 'sm-icon-file-word' : undefined;
    }
  },
  watch: {
    createMode() { this.file = null; this.error = null; }
  },
  mounted() {
    api.remainingCount().then((res) => {
      this.dailyLimit = res.data.daily_limit;
      this.remainingCount = res.data.remaining_count;
    }).catch(() => { this.remainingCount = null; });
    const moduleEl = document.querySelector('.my-module-content');
    if (moduleEl) this.myModuleId = moduleEl.dataset.taskId;
    const emptyEl = document.querySelector('#my_module_is_empty');
    if (emptyEl) this.emptyTask = emptyEl.value === 'true';
  },
  methods: {
    setFile(file) {
      if (file.size > 1024 * this.fileLimitMb * 1024) {
        this.error = `${this.i18n.t('repositories.import_records.dragAndDropUpload.fileTooLargeError')} ${this.fileLimitMb} MB`;
        return false;
      }
      this.error = null;
      this.file = file;
      return true;
    },
    handleError(msg) { this.error = msg; },
    async createProtocol() {
      this.uploading = true;
      this.error = null;
      try {
        const res = await api.createProtocol({ mode: this.createMode, prompt: this.prompt, file: this.file });
        this.parsedProtocolId = res.data.id;
        this.checkDocumentStatus();
      } catch (e) {
        this.uploading = false;
        this.error = e.message || this.i18n.t('ai_parser.modal.document_error');
      }
    },
    async checkDocumentStatus() {
      if (!this.parsedProtocolId) return;
      try {
        const res = await api.showProtocol(this.parsedProtocolId);
        // api.showProtocol 直接返回响应体 { data: { id, attributes } }（非 axios 包裹），
        // 故属性在 res.data.attributes（不是 res.data.data.attributes）。
        const attrs = res.data.attributes;
        if (attrs.status === 'done' && attrs.valid) {
          this.uploading = false;
          this.protocolPreview = attrs.parsed_data;
          this.protocolValid = true;
        } else if (attrs.status === 'rejected') {
          this.uploading = false;
          this.error = attrs.last_error;
        } else if (attrs.status === 'error') {
          this.uploading = false;
          this.error = this.i18n.t('ai_parser.modal.document_error');
        } else if (attrs.status === 'done' && !attrs.valid) {
          this.uploading = false;
          this.error = this.i18n.t('ai_parser.modal.invalid_protocol_error');
        } else {
          setTimeout(() => this.checkDocumentStatus(), 3000);
        }
      } catch (e) {
        this.uploading = false;
        this.error = this.i18n.t('ai_parser.modal.document_error');
      }
    },
    importProtocol() {
      if (!this.emptyTask) {
        this.showConfirmationModal = true;
        return;
      }
      this.doImport('replace');
    },
    async doImport(loadMode) {
      try {
        await api.importProtocol(this.parsedProtocolId, { myModuleId: this.myModuleId, loadMode });
        if (window.HelperModule) {
          window.HelperModule.flashAlertMsg(this.i18n.t('ai_parser.modal.protocol_created_successfully'), 'success');
        }
        if (this.myModuleId) {
          window.location.reload();
        } else if (window.protocolsTable && window.protocolsTable.$refs && window.protocolsTable.$refs.table) {
          window.protocolsTable.$refs.table.updateTable();
          this.onClose();
        } else {
          window.location.reload();
        }
      } catch (e) {
        this.error = e.message || this.i18n.t('ai_parser.modal.document_error');
      }
    },
    closeConfirmation() { this.showConfirmationModal = false; }
  }
};
</script>
