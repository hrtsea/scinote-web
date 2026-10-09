<script setup>
import { onMounted, ref } from 'vue';

// dropdownSelector 由宿主 Sprockets 主包（application.js.erb）全局提供。
// 它在选中时会回写原生 <select> 并触发 change（dropdown_selector.js:605），
// 因此这里只需在挂载时做一次「外观增强」，表单语义仍由原生 select 承担。
const props = defineProps({
  modelValue: { type: String, default: '' },
  options: { type: Array, default: () => [] },
  name: { type: String, required: true },
});

const emit = defineEmits(['update:modelValue']);

const selectEl = ref(null);

onMounted(() => {
  const { jQuery, dropdownSelector } = window;
  if (!jQuery || !dropdownSelector || !selectEl.value) return;

  dropdownSelector.init(jQuery(selectEl.value), {
    singleSelect: true,
    closeOnSelect: true,
    noEmptyOption: true,
    selectAppearance: 'simple',
    disableSearch: true,
  });
});

function onChange(event) {
  emit('update:modelValue', event.target.value);
}
</script>

<template>
  <select ref="selectEl" :name="name" :value="modelValue" @change="onChange">
    <option v-for="option in props.options" :key="option.value" :value="option.value">
      {{ option.label }}
    </option>
  </select>
</template>
