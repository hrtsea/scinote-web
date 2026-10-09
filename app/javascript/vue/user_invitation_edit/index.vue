<script setup>
import { onMounted } from 'vue';
import { applyFormErrors } from '../shared/form_errors.js';

// Server-rendered validation errors for the invitation (set password) form.
// Replaces the old `users/invitations/resource_errors` (model 'user') and
// `users/invitations/team_errors` (model 'team'); both operate on the same
// <form>, processed in user-then-team order to preserve focus behavior.
const props = defineProps({
  userErrors: { type: Object, default: () => ({}) },
  teamErrors: { type: Object, default: () => ({}) },
});

onMounted(() => {
  const forms = Array.from(document.querySelectorAll('form'));
  applyFormErrors(forms, [
    { modelName: 'user', errors: props.userErrors },
    { modelName: 'team', errors: props.teamErrors },
  ]);
});
</script>

<template></template>
