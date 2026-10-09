<script setup>
import { computed, getCurrentInstance, ref } from 'vue';

const props = defineProps({
  // 服务端下发的当前 API key（原值）
  apiKey: { type: String, default: '' },
  createUrl: { type: String, required: true },
  csrfToken: { type: String, default: '' },
  flashError: { type: String, default: '' },
});

const { appContext } = getCurrentInstance();
const i18n = appContext.config.globalProperties.i18n;

// 与迁移前的 label_printers/index.js 完全同构的状态机：
// 仅当「原有 API key 非空」时，输入值与原值不一致才提示 warning 并显示保存按钮，
// 其余情况显示「已保存」。
const originalValue = props.apiKey || '';
const apiKey = ref(originalValue);

const changed = computed(() => originalValue.length > 0 && apiKey.value !== originalValue);
const saveHidden = computed(() => originalValue.length > 0 && apiKey.value === originalValue);
const savedHidden = computed(() => !saveHidden.value);
</script>

<template>
  <div class="collapse-row">
    <i class="sn-icon sn-icon-down" data-toggle="collapse" href="#SettingsSection" aria-expanded="false"></i>
    <div class="row-title">{{ i18n.t('users.settings.account.label_printer.settings') }}</div>
  </div>
  <ul id="SettingsSection" class="collapse in collapse-content">
    <form :action="props.createUrl" method="post">
      <input type="hidden" name="authenticity_token" :value="props.csrfToken">
      <div
        class="api-key-container"
        :class="{ warning: changed }"
        :data-warning="i18n.t('users.settings.account.label_printer.api_key_warning')"
      >
        <div
          class="sci-input-container"
          :class="{ error: !!props.flashError }"
          :data-error-text="props.flashError"
        >
          <label for="label_printer_fluics_api_key">
            {{ i18n.t('users.settings.account.label_printer.api_key_label') }}
          </label>
          <input
            id="label_printer_fluics_api_key"
            v-model="apiKey"
            class="sci-input-field api-key-input"
            type="text"
            name="label_printer[fluics_api_key]"
            :data-original-value="originalValue"
          >
        </div>
        <input
          class="save-button btn btn-primary"
          :class="{ hidden: saveHidden }"
          type="submit"
          :value="i18n.t('general.save')"
        >
        <button class="saved-button btn btn-secondary" :class="{ hidden: savedHidden }" disabled>
          <i class="sn-icon sn-icon-check"></i>
          {{ i18n.t('users.settings.account.label_printer.saved') }}
        </button>
      </div>
    </form>
  </ul>
</template>
