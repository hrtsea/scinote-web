<script setup>
import { computed, getCurrentInstance, reactive, ref } from 'vue';
import MethodSelect from './method_select.vue';

const props = defineProps({
  action: { type: String, required: true },
  methodOptions: { type: Array, default: () => [] },
  // 传 null 表示「新建」；传入 webhook 表示「编辑」
  webhook: { type: Object, default: null },
});

const emit = defineEmits(['cancel', 'saved']);

const { appContext } = getCurrentInstance();
const i18n = appContext.config.globalProperties.i18n;

const isCreate = computed(() => props.webhook === null);
const original = props.webhook || {};

const form = reactive({
  httpMethod: original.http_method || '',
  url: original.url || '',
  includeSerializedSubject: Boolean(original.include_serialized_subject),
  secretKey: original.secret_key || '',
});

const errors = ref({});
let submitting = false;

const urlErrors = computed(() => errors.value.url || []);
const urlErrorText = computed(() => urlErrors.value.join(', '));

// 与旧 renderFormErrors 对齐：url 走 .error + data-error-text，其余走 .help-block
const mappedKeys = ['url', 'http_method', 'secret_key', 'include_serialized_subject'];

function errorBlock(key) {
  return (errors.value[key] || []).map((text) => ({ key, text: `${text}.` }));
}

const genericErrors = computed(() => Object.entries(errors.value)
  .filter(([key]) => !mappedKeys.includes(key))
  .map(([key, messages]) => ({ key, text: `${[].concat(messages).join(', ')}.` })));

function csrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.content : '';
}

function onCancel() {
  if (isCreate.value) {
    form.httpMethod = '';
    form.url = '';
    form.secretKey = '';
    form.includeSerializedSubject = false;
  } else {
    form.url = original.url || '';
  }
  errors.value = {};
  emit('cancel');
}

async function onSubmit(event) {
  event.preventDefault();
  if (submitting) return;
  submitting = true;
  errors.value = {};

  const body = new FormData();
  body.append('webhook[http_method]', form.httpMethod);
  body.append('webhook[url]', form.url);
  body.append('webhook[secret_key]', form.secretKey);
  body.append('webhook[include_serialized_subject]', form.includeSerializedSubject ? '1' : '0');
  if (!isCreate.value) body.append('_method', 'patch');

  try {
    const response = await fetch(props.action, {
      method: 'POST',
      body,
      headers: { 'X-CSRF-Token': csrfToken(), Accept: 'application/json' },
      credentials: 'same-origin',
    });

    if (response.status === 422) {
      const payload = await response.json();
      errors.value = payload.errors || {};
      return;
    }

    // 与 rails-ujs 远程表单一致：成功后跟随服务端 redirect
    window.location.assign(response.url || window.location.href);
    emit('saved');
  } finally {
    submitting = false;
  }
}
</script>

<template>
  <form class="webhook-form" method="post" :action="props.action" @submit="onSubmit">
    <div class="webhook-form-row">
      <span class="form-text webhook-form-trigger-text">{{ i18n.t('webhooks.index.webhook_trigger') }}</span>
      <div class="webhook-method-container">
        <MethodSelect
          v-model="form.httpMethod"
          name="webhook[http_method]"
          :options="props.methodOptions"
        />
        <span v-for="item in errorBlock('http_method')" :key="item.key" class="help-block">{{ item.text }}</span>
      </div>
      <span class="form-text">{{ i18n.t('webhooks.index.target') }}</span>
      <div
        class="sci-input-container url-input-container form-group"
        :class="{ error: urlErrors.length > 0 }"
        :data-error-text="urlErrorText"
      >
        <input
          v-model="form.url"
          class="sci-input-field url-input"
          type="text"
          name="webhook[url]"
          :placeholder="i18n.t('webhooks.index.url_placeholder')"
          :data-original-value="original.url"
        >
      </div>
      <button class="btn btn-light cancel-action" type="button" @click="onCancel">
        <i class="sn-icon sn-icon-close"></i>
        {{ i18n.t('general.cancel') }}
      </button>
      <button class="btn btn-primary save-webhook" type="submit">
        <i class="fas fa-save"></i>
        {{ i18n.t('general.save') }}
      </button>
    </div>
    <div class="webhook-form-row">
      <span class="form-text">{{ i18n.t('webhooks.index.include_serialized_subject') }}</span>
      <div class="sci-input-container form-group">
        <span class="sci-checkbox-container ml-3">
          <input type="hidden" name="webhook[include_serialized_subject]" value="0">
          <input
            v-model="form.includeSerializedSubject"
            class="sci-checkbox"
            type="checkbox"
            name="webhook[include_serialized_subject]"
            value="1"
          >
          <span class="sci-checkbox-label"></span>
        </span>
        <small>{{ i18n.t('webhooks.index.include_serialized_subject_hint') }}</small>
        <span v-for="item in errorBlock('include_serialized_subject')" :key="item.key" class="help-block">{{ item.text }}</span>
      </div>
    </div>
    <div class="webhook-form-row">
      <span class="form-text webhook-form-secret-key-text">{{ i18n.t('webhooks.index.secret_key') }}</span>
      <div class="webhook-secret-key-container">
        <div class="sci-input-container form-group">
          <input
            v-model="form.secretKey"
            class="sci-input-field"
            type="text"
            name="webhook[secret_key]"
          >
          <small>{{ i18n.t('webhooks.index.secret_key_hint') }}</small>
          <span v-for="item in errorBlock('secret_key')" :key="item.key" class="help-block">{{ item.text }}</span>
        </div>
      </div>
    </div>
    <div v-for="item in genericErrors" :key="item.key">
      <span class="help-block">{{ item.text }}</span>
    </div>
  </form>
</template>
