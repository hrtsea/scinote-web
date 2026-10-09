<script setup>
import { computed, getCurrentInstance, nextTick, ref, watch } from 'vue';
import {
  clearFormErrors,
  getCsrfToken,
  showFormErrors,
  submitRegistrationForm,
} from './form_helpers.js';

const props = defineProps({
  // { form_id, form_class, sso_enabled, sso_provider_enabled, disable_local_passwords }
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
  // All password fields use data-role='clear' and are reset on cancel,
  // matching the original `form.find("input[data-role='clear']").val('')`.
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
    <input type="hidden" name="user[change_password]" value="true" />
    <div data-part="view" v-show="!props.editing">
      <div class="form-group">
        <h3>{{ i18n.t("users.registrations.edit.password_label") }}</h3>
        <div class="user-attribute">
          ••••••••••••
          <a
            href="#"
            class="btn btn-secondary"
            :class="{ disabled: props.data.sso_enabled && props.data.sso_provider_enabled && props.data.disable_local_passwords }"
            data-action="edit"
            @click.prevent="onEdit"
          >{{ i18n.t("general.change") }}</a>
        </div>
      </div>
    </div>
    <div data-part="edit" v-show="props.editing">
      <div class="well">
        <h4>{{ i18n.t("users.registrations.edit.password_title") }}</h4>
        <div class="form-group sci-input-container password-input-container">
          <label for="edit-password-current-password">
            {{ i18n.t("users.registrations.edit.current_password_label") }}
            <i>{{ i18n.t("users.registrations.edit.password_explanation") }}</i>
          </label>
          <div class="password-icon-wrapper">
            <input
              type="password"
              name="user[current_password]"
              id="edit-password-current-password"
              autocomplete="off"
              class="form-control sci-input-field"
              data-role="clear"
            />
          </div>
        </div>
        <div class="form-group sci-input-container password-input-container">
          <label for="user_password">{{ i18n.t("users.registrations.edit.new_password_label") }}</label>
          <div class="password-icon-wrapper">
            <input
              type="password"
              name="user[password]"
              id="user_password"
              autocomplete="off"
              class="form-control sci-input-field"
              data-role="clear"
            />
          </div>
        </div>
        <div class="form-group sci-input-container password-input-container">
          <label for="user_password_confirmation">{{ i18n.t("users.registrations.edit.new_password_2_label") }}</label>
          <div class="password-icon-wrapper">
            <input
              type="password"
              name="user[password_confirmation]"
              id="user_password_confirmation"
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
