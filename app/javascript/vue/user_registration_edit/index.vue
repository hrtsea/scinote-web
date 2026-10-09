<script setup>
import { ref } from 'vue';
import EmailForm from './email_form.vue';
import PasswordForm from './password_form.vue';

const props = defineProps({
  // { value, form_id, form_class, sso_enabled, sso_provider_enabled,
  //   confirmable, pending_reconfirmation, unconfirmed_email }
  email: { type: Object, required: true },
  // { form_id, form_class, sso_enabled, sso_provider_enabled, disable_local_passwords }
  password: { type: Object, required: true },
  updateUrl: { type: String, required: true },
});

// Only one inline-edit form open at a time (mirrors the original
// `_.each(forms, toggleFormVisibility(form, false))` that closed every
// other form before opening the clicked one).
const editing = ref(null);

function startEdit(which) {
  editing.value = which;
}

function cancelEdit() {
  editing.value = null;
}
</script>

<template>
  <div class="user-registration-edit-forms">
    <email-form
      :data="props.email"
      :update-url="props.updateUrl"
      :editing="editing === 'email'"
      @edit="startEdit('email')"
      @cancel="cancelEdit"
    />
    <password-form
      :data="props.password"
      :update-url="props.updateUrl"
      :editing="editing === 'password'"
      @edit="startEdit('password')"
      @cancel="cancelEdit"
    />
  </div>
</template>
