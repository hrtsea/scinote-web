<template>
  <div class="ai-parser-root">
    <!-- 官方同构：一个隐藏触发器 + 弹窗（v-if） -->
    <button id="importWithAI" class="tw-hidden" type="button" @click="open()"></button>

    <div
      v-if="visible"
      class="modal in"
      tabindex="-1"
      role="dialog"
      style="z-index: 2040; display: block;"
    >
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <div class="modal-header">
            <button type="button" class="close" :aria-label="t('close')" @click="close()">
              <i class="sn-icon sn-icon-close"></i>
            </button>
            <h2 class="modal-title">{{ title }}</h2>
          </div>

          <!-- ① 付费墙：非 Premium -->
          <div v-if="!premium" class="modal-body">
            <div class="flex items-center justify-center">
              <img src="/images/scinote/core/common/premium_upgrade.svg" class="mb-3" alt="" />
            </div>
            <h2>{{ t('upgrade_title') }}</h2>
            <p>{{ t('upgrade_body') }}</p>
            <div class="modal-footer">
              <a :href="learnMoreUrl" class="btn btn-secondary" target="_blank">{{ t('learn_more') }}</a>
              <a :href="upgradeUrl" class="btn btn-primary" target="_blank">{{ t('upgrade') }}</a>
            </div>
          </div>

          <!-- ② 正常流程 -->
          <template v-else>
            <div class="modal-body">
              <p class="text-muted">{{ t('how_to_use_title') }}</p>
              <ol class="ai-parser-steps">
                <li
                  v-for="(b, i) in informationBlocks"
                  :key="b.key"
                  :class="{ 'is-active': i + 1 === step, 'is-done': i + 1 < step }"
                >
                  <strong>{{ b.label }}</strong> — <span>{{ b.description }}</span>
                </li>
              </ol>

              <!-- 输入区（step <= 3） -->
              <template v-if="step <= 3">
                <div class="form-group">
                  <label>{{ t('mode_label') }}</label>
                  <div class="ai-parser-modes">
                    <label><input type="radio" value="prompt_only" v-model="mode" /> {{ t('prompt_only') }}</label>
                    <label><input type="radio" value="file_upload" v-model="mode" /> {{ t('file_upload') }}</label>
                  </div>
                </div>

                <div class="form-group" v-if="mode === 'file_upload'">
                  <label>{{ t('upload') }}</label>
                  <input type="file" accept=".pdf" class="form-control" @change="onFile" />
                  <small class="text-muted">{{ t('file_hint') }}</small>
                </div>

                <div class="form-group">
                  <label>{{ t('prompt_label') }}</label>
                  <textarea
                    v-model="prompt"
                    rows="4"
                    class="form-control"
                    :placeholder="t('prompt_placeholder')"
                  ></textarea>
                  <small class="text-muted">{{ t('supporting_text') }}</small>
                </div>

                <div v-if="error" class="alert alert-danger">{{ error }}</div>
              </template>

              <!-- 结果审阅区（step >= 4） -->
              <template v-else>
                <div v-if="created" class="alert alert-success">{{ t('protocol_created_successfully') }}</div>
                <template v-else>
                  <div class="form-group">
                    <label>{{ t('name_label') }}</label>
                    <input v-model="draft.name" class="form-control" />
                  </div>
                  <div class="form-group">
                    <label>{{ t('description_label') }}</label>
                    <textarea v-model="draft.description" rows="3" class="form-control"></textarea>
                  </div>
                  <h4>{{ t('steps_label') }}</h4>
                  <div v-for="(s, i) in draft.steps" :key="i" class="well">
                    <div class="form-group">
                      <input v-model="s.name" class="form-control" :placeholder="t('step_name_placeholder')" />
                    </div>
                    <div class="form-group">
                      <textarea v-model="s.description" rows="3" class="form-control"
                                :placeholder="t('step_description_placeholder')"></textarea>
                    </div>
                  </div>
                </template>
              </template>
            </div>

            <div class="modal-footer">
              <span class="text-muted mr-auto" v-if="quota && quota.limit">
                {{ t('quota_label') }}: {{ quota.used }} / {{ quota.limit }}
              </span>
              <button v-if="step <= 3" type="button" class="btn btn-primary"
                      :disabled="loading || !canGenerate" @click="generate()">
                <span v-if="loading" class="spinner"></span>
                {{ loading ? t('generating') : t('generate') }}
              </button>
              <button v-else-if="!created" type="button" class="btn btn-success"
                      :disabled="loading" @click="create()">
                {{ loading ? t('creating') : t('create_template') }}
              </button>
              <button v-else type="button" class="btn btn-primary" @click="close()">{{ t('close') }}</button>
            </div>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { parseProtocol, createDraft } from './api.js';

// SSR 注入的 window 全局先落根组件 data —— in-DOM 模板只白名单少量全局，
// 直接在模板里引用 window 会拿不到值（本仓已知坑）。
const CFG = (typeof window !== 'undefined' && window.__AI_PARSER_CONFIG__) || {};

export default {
  name: 'AiParserModal',
  data() {
    const i18n = CFG.i18n || {};
    return {
      parseUrl: CFG.parseUrl || '/ai_protocols/parse',
      createUrl: CFG.createUrl || '/ai_protocols/create_draft',
      learnMoreUrl: CFG.learnMoreUrl || 'https://knowledgebase.scinote.net/en/knowledge/ai-protocol-parser',
      upgradeUrl: CFG.upgradeUrl || 'https://www.scinote.net/get-a-quote-pricing/',
      premium: CFG.premium !== false,
      title: i18n.title || 'Create with AI',
      _i18n: i18n,

      visible: false,
      step: 1,
      mode: 'file_upload',
      prompt: '',
      file: null,
      loading: false,
      error: null,
      created: false,
      quota: CFG.quota || { used: 0, limit: 5 },
      draft: { name: '', description: '', steps: [] },

      informationBlocks: [
        { key: 'select_option', label: i18n.select_option_label || 'Select option',
          description: i18n.select_option_desc || 'Choose prompt only or upload a PDF file.' },
        { key: 'write_prompt', label: i18n.write_prompt_label || 'Write prompt',
          description: i18n.write_prompt_desc || 'Describe how the AI should extract the protocol.' },
        { key: 'generate', label: i18n.generate_label || 'Generate',
          description: i18n.generate_desc || 'The AI turns your input into structured steps.' },
        { key: 'review', label: i18n.review_label || 'Review',
          description: i18n.review_desc || 'Check the description and the step list.' },
        { key: 'create_template', label: i18n.create_template_label || 'Create template',
          description: i18n.create_template_desc || 'Save the result as a draft protocol template.' },
      ],
    };
  },
  computed: {
    canGenerate() {
      if (this.mode === 'file_upload' && !this.file) return false;
      return (this.prompt || '').trim().length > 0 || this.mode === 'file_upload';
    },
  },
  mounted() {
    // 可见入口（Protocol actions 下拉项）由服务端注入，点击后广播此事件。
    document.addEventListener('ai-parser:open', this.open);
    // 官方同构触发器：外部亦可直接 click #importWithAI
    const trigger = document.getElementById('importWithAI');
    if (trigger) trigger.addEventListener('click', this.open);
  },
  beforeUnmount() {
    document.removeEventListener('ai-parser:open', this.open);
  },
  methods: {
    t(key) {
      const dict = this._i18n || {};
      return dict[key] || key;
    },
    open() {
      this.visible = true;
      this.step = 1;
      this.error = null;
      this.created = false;
    },
    close() {
      this.visible = false;
      this.loading = false;
    },
    onFile(e) {
      this.file = (e.target.files && e.target.files[0]) || null;
    },
    async generate() {
      this.loading = true;
      this.error = null;
      this.step = 3;
      try {
        const data = await parseProtocol(this.parseUrl, {
          mode: this.mode, prompt: this.prompt, file: this.file,
        });
        this.draft = {
          name: data.protocol ? data.protocol.name : '',
          description: data.protocol ? data.protocol.description : '',
          steps: (data.steps || []).map((s) => ({
            name: s.name || '', description: s.description || '', tables: s.tables || [],
          })),
        };
        if (data.quota) this.quota = data.quota;
        this.step = 4;
      } catch (e) {
        const resp = e && e.response;
        if (resp && resp.data && resp.data.quota) this.quota = resp.data.quota;
        this.error = (resp && resp.data && resp.data.error) || this.t('generate_error');
        this.step = 2;
      } finally {
        this.loading = false;
      }
    },
    async create() {
      this.loading = true;
      this.error = null;
      try {
        const data = await createDraft(this.createUrl, this.draft);
        this.created = true;
        this.step = 5;
        if (data && data.url) window.location.href = data.url;
      } catch (e) {
        this.error = (e && e.response && e.response.data && e.response.data.error) || this.t('create_error');
      } finally {
        this.loading = false;
      }
    },
  },
};
</script>

<style scoped>
.ai-parser-steps { padding-left: 18px; margin: 8px 0 16px; }
.ai-parser-steps li { color: #888780; font-size: 13px; line-height: 1.6; }
.ai-parser-steps li.is-active { color: #0C447C; font-weight: 500; }
.ai-parser-steps li.is-done { color: #3B6D11; }
.ai-parser-modes { display: flex; gap: 16px; }
.mr-auto { margin-right: auto; }
</style>
