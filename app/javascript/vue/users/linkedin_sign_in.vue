<template>
  <img :src="current" class="linkedin-signin-button" alt="Sign in with LinkedIn"
       @mouseover="current = hoverSrc"
       @mouseout="current = defaultSrc"
       @click="current = clickSrc" />
</template>

<script setup>
import { ref, watch } from 'vue';

const props = defineProps({
  defaultSrc: { type: String, default: '' },
  hoverSrc: { type: String, default: '' },
  clickSrc: { type: String, default: '' }
});

const current = ref(props.defaultSrc);

watch(() => props.defaultSrc, (value) => { current.value = value; });
</script>
