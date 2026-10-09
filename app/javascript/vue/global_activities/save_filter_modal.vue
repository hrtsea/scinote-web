<script setup>
// 保存筛选条件模态框的「名称输入 + 保存按钮」交互。
// 原 Gen-1（index.js）行为：输入非空才可点保存；保存时 POST 到 save-filter-url，
// 参数 name + filter: globalActivities.getFilters()，成功/失败用 HelperModule.flashAlertMsg 提示并关弹窗。
// 模态框外壳（.modal / .modal-dialog / data-dismiss）仍由服务端渲染 + Bootstrap 委托管理。
import { getCurrentInstance, ref } from 'vue';

const props = defineProps({
  saveFilterUrl: { type: String, required: true },
});

const { appContext } = getCurrentInstance();
const i18n = appContext.config.globalProperties.i18n;

const filterName = ref('');
const confirmDisabled = ref(true);

function jQuery() {
  return window.jQuery;
}

function onInput() {
  confirmDisabled.value = filterName.value.length === 0;
}

function save() {
  const $ = jQuery();
  if (!$ || !window.globalActivities || confirmDisabled.value) return;

  $.ajax({
    url: props.saveFilterUrl,
    type: 'POST',
    global: false,
    dataType: 'json',
    data: {
      name: filterName.value,
      filter: window.globalActivities.getFilters(),
    },
    success(data) {
      if (window.HelperModule) window.HelperModule.flashAlertMsg(data.message, 'success');
      filterName.value = '';
      confirmDisabled.value = true;
      $('#saveFilterModal').modal('hide');
    },
    error(response) {
      if (window.HelperModule) {
        window.HelperModule.flashAlertMsg(response.responseJSON.errors.join(','), 'danger');
      }
    },
  });
}
</script>

<template>
  <div class="modal-body">
    <p>
      {{ i18n.t('global_activities.index.save_filter_modal.description') }}
    </p>
    <div class="sci-input-container">
      <label>{{ i18n.t('global_activities.index.save_filter_modal.filter_name_label') }}</label>
      <input
        type="text"
        class="sci-input-field activity-filter-name-input"
        :placeholder="i18n.t('global_activities.index.save_filter_modal.filter_name_placeholder')"
        v-model="filterName"
        @keyup="onInput"
      >
    </div>
  </div>
  <div class="modal-footer">
    <button type="button" class="btn btn-secondary" data-dismiss="modal">
      {{ i18n.t('general.cancel') }}
    </button>
    <button
      type="button"
      class="btn btn-primary btn-confirm"
      :data-save-filter-url="saveFilterUrl"
      :disabled="confirmDisabled"
      @click="save"
    >
      {{ i18n.t('general.save') }}
    </button>
  </div>
</template>
