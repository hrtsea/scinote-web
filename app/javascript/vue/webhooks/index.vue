<script setup>
import { computed, getCurrentInstance, onBeforeUnmount, ref } from 'vue';
import WebhookForm from './webhook_form.vue';

const props = defineProps({
  // 每个 filter: { id, name, info_url, create_url, webhooks: [...] }
  filters: { type: Array, default: () => [] },
  // { destroy_filter: String }
  urls: { type: Object, required: true },
  methodOptions: { type: Array, default: () => [] },
});

const { appContext } = getCurrentInstance();
const i18n = appContext.config.globalProperties.i18n;

const filterInfo = ref({});
const infoRequested = ref({});
const createOpenId = ref(null);
const editingWebhookId = ref(null);
const deleteTarget = ref({ id: null, name: '' });

const csrfParam = computed(() => {
  const meta = document.querySelector('meta[name="csrf-param"]');
  return meta ? meta.content : 'authenticity_token';
});
const csrfValue = computed(() => {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.content : '';
});

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

const deleteDescription = computed(() => i18n
  .t('webhooks.index.delete_filter_modal.description_html')
  .replace('<b></b>', `<b>${escapeHtml(deleteTarget.value.name)}</b>`));

function jQuery() {
  return window.jQuery;
}

// 「应用的活动过滤器」下拉：首次展开时懒加载（与旧实现一致，只请求一次）
function loadInfo(filter) {
  if (infoRequested.value[filter.id]) return;
  infoRequested.value = { ...infoRequested.value, [filter.id]: true };

  fetch(filter.info_url, { headers: { Accept: 'application/json' }, credentials: 'same-origin' })
    .then((response) => (response.ok ? response.json() : { filter_elements: [] }))
    .then((data) => {
      filterInfo.value = { ...filterInfo.value, [filter.id]: data.filter_elements || [] };
    })
    .catch(() => {
      filterInfo.value = { ...filterInfo.value, [filter.id]: [] };
    });
}

// Bootstrap 3 的 collapse 走 document 上的 data-api 委托，这里只需补一次 programmatic show
function openCreate(filter) {
  createOpenId.value = filter.id;
  const $ = jQuery();
  if ($) $(`#activityFilter${filter.id}`).collapse('show');
}

function closeCreate() {
  createOpenId.value = null;
}

function openEdit(webhook) {
  editingWebhookId.value = webhook.id;
}

function closeEdit() {
  editingWebhookId.value = null;
}

function onSaved() {
  closeCreate();
  closeEdit();
}

// 删除过滤器模态框：先写入目标，再由 Bootstrap 的 data-toggle="modal" 打开
function selectDeleteTarget(filter) {
  deleteTarget.value = { id: filter.id, name: filter.name };
}

// 卸载时清理 Bootstrap 注入到 body 的 backdrop（turbolinks 换页缓存会保留 body）
onBeforeUnmount(() => {
  const $ = jQuery();
  if (!$) return;
  $('.modal-backdrop').remove();
  $('body').removeClass('modal-open').css('padding-right', '');
});
</script>

<template>
  <div class="webhooks-index-body">
    <ul class="activity-filters-list">
      <li v-for="filter in props.filters" :key="filter.id" class="filter-element">
        <div class="filter-block">
          <i
            class="sn-icon sn-icon-down collapsed"
            data-toggle="collapse"
            :href="`#activityFilter${filter.id}`"
            aria-expanded="false"
          ></i>
          <span class="filter-name" :title="filter.name">{{ filter.name }}</span>

          <div class="info-container dropdown" :data-url="filter.info_url">
            <div
              :id="`filter-info-${filter.id}-button`"
              class="btn btn-light show-filter icon-btn"
              data-toggle="dropdown"
              @click="loadInfo(filter)"
            >
              <i class="sn-icon sn-icon-info"></i>
            </div>
            <div class="dropdown-menu" :aria-labelledby="`filter-info-${filter.id}-button`" role="menu">
              <p class="filter-info-title">{{ i18n.t('webhooks.index.applied_filters') }}</p>
              <div class="tags-list">
                <span
                  v-for="(element, index) in (filterInfo[filter.id] || [])"
                  :key="index"
                  class="filter-info-tag"
                >{{ element }}</span>
              </div>
            </div>
          </div>

          <div class="btn btn-light create-webhook" @click="openCreate(filter)">
            <i class="sn-icon sn-icon-new-task"></i>
            {{ i18n.t('webhooks.index.new_webhook') }}
          </div>

          <div
            class="btn btn-light delete-filter icon-btn"
            :data-id="filter.id"
            :data-name="filter.name"
            data-toggle="modal"
            data-target="#deleteFilterModal"
            @click="selectDeleteTarget(filter)"
          >
            <i class="sn-icon sn-icon-delete"></i>
          </div>
        </div>

        <ul class="webhooks-list collapse" :id="`activityFilter${filter.id}`">
          <li class="create-webhook-container" :class="{ hidden: createOpenId !== filter.id }">
            <WebhookForm
              :action="filter.create_url"
              :method-options="props.methodOptions"
              :webhook="null"
              @cancel="closeCreate"
              @saved="onSaved"
            />
          </li>

          <li
            v-for="webhook in filter.webhooks"
            :key="webhook.id"
            class="webhook"
            :class="{ active: webhook.active }"
          >
            <div class="view-mode" :class="{ hidden: editingWebhookId === webhook.id }">
              <span class="webhook-text" :title="webhook.url" v-html="i18n.t('webhooks.index.webhook_text_html', { method: webhook.http_method.toUpperCase(), url: webhook.url })"></span>
              <span v-if="webhook.active" class="active-webhook">
                <i class="fas fa-check-circle"></i>
                {{ i18n.t('webhooks.index.active') }}
              </span>
              <span v-else class="disabled-webhook">
                <i class="fas fa-unlink"></i>
                {{ i18n.t('webhooks.index.disabled') }}
              </span>
              <div class="dropdown webhook-menu">
                <button
                  :id="`webhookMenuButton${webhook.id}`"
                  class="btn btn-light icon-btn dropdown-toggle"
                  type="button"
                  data-toggle="dropdown"
                  aria-haspopup="true"
                  aria-expanded="true"
                >
                  <span><i class="sn-icon sn-icon-more-hori"></i></span>
                </button>
                <ul class="dropdown-menu dropdown-menu-right" :aria-labelledby="`webhookMenuButton${webhook.id}`">
                  <li class="divider-label">{{ i18n.t('webhooks.index.webhook_options').toUpperCase() }}</li>
                  <li>
                    <a href="#" class="edit-webhook" @click.prevent="openEdit(webhook)">
                      <i class="sn-icon sn-icon-edit"></i>
                      {{ i18n.t('general.edit') }}
                    </a>
                  </li>
                  <li>
                    <a
                      :href="webhook.active ? webhook.disable_url : webhook.enable_url"
                      data-method="patch"
                      rel="nofollow"
                    >
                      <i :class="webhook.active ? 'fas fa-unlink' : 'fas fa-check-circle'"></i>
                      {{ webhook.active ? i18n.t('webhooks.index.disable') : i18n.t('webhooks.index.enable') }}
                    </a>
                  </li>
                  <li>
                    <a
                      :href="webhook.delete_url"
                      data-method="delete"
                      rel="nofollow"
                      :data-confirm="i18n.t('webhooks.index.delete_webhook_confimration')"
                    >
                      <i class="sn-icon sn-icon-delete"></i>
                      {{ i18n.t('general.delete') }}
                    </a>
                  </li>
                </ul>
              </div>
            </div>
            <div class="edit-webhook-container" :class="{ hidden: editingWebhookId !== webhook.id }">
              <WebhookForm
                :action="webhook.update_url"
                :method-options="props.methodOptions"
                :webhook="webhook"
                @cancel="closeEdit"
                @saved="onSaved"
              />
            </div>
          </li>
        </ul>
      </li>
    </ul>

    <div id="deleteFilterModal" class="modal" tabindex="-1" role="dialog">
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <div class="modal-header">
            <button
              type="button"
              class="close"
              data-dismiss="modal"
              :aria-label="i18n.t('general.close')"
            >
              <i class="sn-icon sn-icon-close"></i>
            </button>
            <h4 class="modal-title">{{ i18n.t('webhooks.index.delete_filter_modal.title') }}</h4>
          </div>
          <div class="modal-body">
            <p class="description" v-html="deleteDescription"></p>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-dismiss="modal">
              {{ i18n.t('general.cancel') }}
            </button>
            <form class="delete-filter-form" method="post" :action="props.urls.destroy_filter">
              <input type="hidden" :name="csrfParam" :value="csrfValue">
              <input type="hidden" name="filter_id" :value="deleteTarget.id">
              <button type="submit" class="btn btn-danger">{{ i18n.t('general.delete') }}</button>
            </form>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
