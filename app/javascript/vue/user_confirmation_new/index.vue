<script setup>
import { onMounted } from 'vue';
import { applyFormErrors } from '../shared/form_errors.js';

// Server-rendered validation errors for the confirmation (resend) form.
// Matches the old `users/confirmation/new.js` which called
//   $('form').renderFormErrors('user', formErrors, false)
const props = defineProps({
  errors: { type: Object, default: () => ({}) },
});

onMounted(() => {
  const forms = Array.from(document.querySelectorAll('form'));
  applyFormErrors(forms, [{ modelName: 'user', errors: props.errors }]);
});
</script>

<template></template>
