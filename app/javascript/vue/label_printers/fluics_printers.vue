<script setup>
import { computed, getCurrentInstance } from 'vue';

const props = defineProps({
  canManage: { type: Boolean, default: false },
  apiKey: { type: String, default: '' },
  printers: { type: Array, default: () => [] },
  createUrl: { type: String, required: true },
  csrfToken: { type: String, default: '' },
});

const { appContext } = getCurrentInstance();
const i18n = appContext.config.globalProperties.i18n;

// 与迁移前 form_with 的 disabled: @fluics_api_key.blank? 对齐
const apiKeyBlank = computed(() => !props.apiKey || props.apiKey.length === 0);
</script>

<template>
  <div class="collapse-row">
    <i class="sn-icon sn-icon-down" data-toggle="collapse" href="#PrintersSection" aria-expanded="false"></i>
    <div class="row-title">Printers</div>
    <div v-if="props.canManage" class="update-printers">
      <form :action="props.createUrl" method="post">
        <input type="hidden" name="authenticity_token" :value="props.csrfToken">
        <input type="hidden" name="label_printer[fluics_api_key]" :value="props.apiKey">
        <button type="submit" class="btn btn-light" :disabled="apiKeyBlank">
          <i class="fas fa-sync"></i>
          {{ i18n.t('users.settings.account.label_printer.update_printers') }}
        </button>
      </form>
    </div>
  </div>
  <ul id="PrintersSection" class="collapse in collapse-content">
    <li v-for="printer in props.printers" :key="printer.id">
      <b>{{ printer.name }}</b> • {{ printer.description }}
    </li>
    <li v-if="props.printers.length === 0">
      {{ i18n.t('users.settings.account.label_printer.no_printers_available') }}
    </li>
  </ul>
</template>
