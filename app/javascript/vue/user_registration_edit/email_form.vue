<script setup>
import { computed, getCurrentInstance, nextTick, ref, watch } from 'vue';
import {
  clearFormErrors,
  getCsrfToken,
  showFormErrors,
  submitRegistrationForm,
} from './form_helpers.js';

const props = defineProps({
  // { value, form_id, form_class, sso_enabled, sso_provider_enabled,
  //   confirmable, pending_reconfirmation, unconfirmed_email }
  data: { type: Object, required: true },
  updateUrl: { type: String, required: true },
  editing: { type: Boolean, default: false },
});

const emit = defineEmits(['edit', 'cancel']);

const { appContext } = getCurrentInstance();
const i18n = appContext.config.globalProperties.i18n;

const formRef = ref(null);
const csrfToken = computed(() => getCsrfToken());

function onEdit() {
  emit('edit');
}

function onCancel() {
  // Clear `data-role='clear'` fields; the email field (data-role='edit',
  // no `data-role='src'`) keeps its value, exactly like the original.
  const formEl = formRef.value;
  if (formEl) {
    clearFormErrors(formEl);
    formEl.querySelectorAll("input[data-role='clear']").forEach((el) => { el.value = ''; });
  }
  emit('cancel');
}

async function onSubmit() {
  const formEl = formRef.value;
  if (!formEl) return;
  clearFormErrors(formEl);
  const result = await submitRegistrationForm(formEl, props.updateUrl, csrfToken.value);
  if (!result.ok) showFormErrors(formEl, result.errors);
}

// When entering edit mode: focus the first text input and (re)initialize the
// show-password eye icons, matching the original `initShowPassword()` call.
watch(() => props.editing, (isEditing) => {
  if (!isEditing) return;
  nextTick(() => {
    const formEl = formRef.value;
    if (formEl) {
      const input = formEl.querySelector("input:not([type='file']):not([type='submit'])");
      if (input) input.focus();
    }
    if (typeof window.initShowPassword === 'function') window.initShowPassword();
  });
});
</script>

<template>
  <form
    ref="form"
    :id="props.data.form_id"
    :class="props.data.form_class"
    :action="props.updateUrl"
    method="post"
    @submit.prevent="onSubmit"
  >
    <div data-part="view" v-show="!props.editing">
      <div class="form-group">
        <h3>{{ i18n.t("users.registrations.edit.email_label") }}</h3>
        <div class="user-attribute">
          {{ props.data.value }}
          <a
            href="#"
            class="btn btn-secondary"
            :class="{ disabled: props.data.sso_enabled && props.data.sso_provider_enabled }"
            data-action="edit"
            @click.prevent="onEdit"
          >{{ i18n.t("general.change") }}</a>
        </div>
        <div
          v-if="props.data.confirmable && props.data.pending_reconfirmation"
          class="alert alert-info"
          style="margin-top: 15px;"
          role="alert"
        >
          <span class="sn-icon sn-icon-info" aria-hidden="true"></span>
          {{ i18n.t("users.registrations.edit.waiting_for_confirm", { email: props.data.unconfirmed_email }) }}
        </div>
      </div>
    </div>
    <div data-part="edit" v-show="props.editing">
      <div class="well">
        <h4>{{ i18n.t("users.registrations.edit.email_title") }}</h4>
        <div class="form-group sci-input-container">
          <label for="user_email">{{ i18n.t("users.registrations.edit.new_email_label") }}</label>
          <input
            type="email"
            name="user[email]"
            id="user_email"
            class="form-control sci-input-field"
            data-role="edit"
          />
        </div>
        <div class="form-group sci-input-container password-input-container">
          <label for="edit-email-current-password">
            {{ i18n.t("users.registrations.edit.current_password_label") }}
            <i>{{ i18n.t("users.registrations.edit.password_explanation") }}</i>
          </label>
          <div class="password-icon-wrapper">
            <input
              type="password"
              name="user[current_password]"
              id="edit-email-current-password"
              autocomplete="off"
              class="form-control sci-input-field"
              data-role="clear"
            />
          </div>
        </div>
        <div class="align-right">
          <a href="#" class="btn btn-light" data-action="cancel" @click.prevent="onCancel">
            {{ i18n.t("general.cancel") }}
          </a>
          <button type="submit" class="btn btn-success">{{ i18n.t("general.save") }}</button>
        </div>
      </div>
    </div>
  </form>
</template>
