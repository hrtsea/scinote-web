<script setup>
import { getCurrentInstance, onBeforeUnmount, onMounted, ref } from 'vue';

const { appContext } = getCurrentInstance();
const i18n = appContext.config.globalProperties.i18n;

const printers = ref([]);
// zebraPrint.init 会同步触发一次 beforeRefresh（即进入「搜索中」态）
const searching = ref(true);
let zebraPrinter = null;

function statusClass(device) {
  return device.status ? device.status.toLowerCase() : '';
}

onMounted(() => {
  // ⚠ 交给 zebraPrint 的容器必须是「游离节点」：
  // zebraPrint 在收到首个设备时会直接对 selector 调用 .empty()，
  // 若把 Vue 正在渲染的 <ul> 交出去，会被外部清空、造成 vdom 与真实 DOM 脱节。
  // 因此打印器列表完全由 Vue 渲染（见下方 v-for），zebraPrint 只负责「发现设备」。
  const detachedSelector = $(document.createElement('ul'));

  try {
    zebraPrinter = window.zebraPrint.init(detachedSelector, {
      clearSelectorOnFirstDevice: true,
      noDevices: () => {
        printers.value = [];
        searching.value = false;
      },
      appendDevice: (device) => {
        printers.value = [...printers.value, device];
        searching.value = false;
      },
      beforeRefresh: () => {
        printers.value = [];
        searching.value = true;
      },
    }, true);
  } catch (error) {
    // 与 zebraPrint 内部 catch 行为一致：无法搜索设备时展示「无可用打印器」
    printers.value = [];
    searching.value = false;
  }
});

function refresh() {
  if (zebraPrinter) zebraPrinter.refreshList();
}

onBeforeUnmount(() => {
  zebraPrinter = null;
});
</script>

<template>
  <div class="collapse-row">
    <i class="sn-icon sn-icon-down" data-toggle="collapse" href="#PrintersSection" aria-expanded="false"></i>
    <div class="row-title">Printers</div>
    <div class="update-printers">
      <button type="submit" class="btn btn-light zebra-printer-refresh" @click.prevent="refresh">
        <i class="fas fa-sync"></i>
        {{ i18n.t('users.settings.account.label_printer.update_printers') }}
      </button>
    </div>
  </div>
  <ul id="PrintersSection" class="collapse in zebra-printers collapse-content">
    <li v-if="searching" class="searching-printers">
      <img src="/images/medium/loading.svg">
      {{ i18n.t('users.settings.account.label_printer.looking_for_printers') }}
    </li>
    <li v-for="(device, index) in printers" :key="`${device.name}-${index}`">
      {{ device.name }}
      <span :class="['zebra-status-tag', statusClass(device)]">{{ device.status }}</span>
    </li>
    <li v-if="!searching && printers.length === 0">
      {{ i18n.t('users.settings.account.label_printer.no_printers_available') }}
    </li>
  </ul>
</template>
