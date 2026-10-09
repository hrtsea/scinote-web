<template>
  <span class="new-protocol-modal-island"></span>
</template>

<script setup>
import { onMounted, onBeforeUnmount } from 'vue';
import $ from 'jquery';

const MODAL = '#newProtocolModal';
const ROLE_SELECTOR = `${MODAL} #protocol_role_selector`;
const NS = '.newProtocolModalIsland';

let $modal = null;

onMounted(() => {
  const modal = document.querySelector(MODAL);
  if (!modal) return;

  $modal = $(modal);

  const submitButton = modal.querySelector('.create-protocol-button');
  const roleWrapper = modal.querySelector('#roleSelectWrapper');
  const hiddenRole = modal.querySelector('#protocol_default_public_user_role_id');
  const minLength = window.GLOBAL_CONSTANTS?.NAME_MIN_LENGTH ?? 2;

  if (window.dropdownSelector) {
    window.dropdownSelector.init(ROLE_SELECTOR, {
      noEmptyOption: true,
      singleSelect: true,
      closeOnSelect: true,
      selectAppearance: 'simple',
      onChange: function() {
        if (hiddenRole) hiddenRole.value = window.dropdownSelector.getValues(ROLE_SELECTOR);
      }
    });
  }

  if (submitButton) submitButton.setAttribute('disabled', 'disabled');

  $modal
    .on(`input${NS}`, '#protocol_name', function() {
      if (!submitButton) return;
      if (this.value.length !== 0 || this.value.length >= minLength) {
        submitButton.removeAttribute('disabled');
      } else {
        submitButton.setAttribute('disabled', 'disabled');
      }
    })
    .on(`change${NS}`, '#protocol_visibility', function() {
      const checked = this.checked;
      if (roleWrapper) roleWrapper.classList.toggle('hidden', !checked);
      if (hiddenRole) hiddenRole.disabled = !checked;
    })
    .on(`submit${NS}`, function() {
      if (submitButton) submitButton.setAttribute('disabled', 'disabled');
    })
    .on(`ajax:error${NS}`, 'form', function(e, error) {
      const msg = error && error.responseJSON ? error.responseJSON.error : null;
      if (msg && window.HelperModule) window.HelperModule.flashAlertMsg(msg, 'danger');
    })
    .on(`ajax:success${NS}`, 'form', function(e, data) {
      if (data && data.message && window.HelperModule) {
        window.HelperModule.flashAlertMsg(data.message, 'success');
      }
      const nameInput = modal.querySelector('#protocol_name');
      if (nameInput && nameInput.parentElement) nameInput.parentElement.classList.remove('error');
      if (submitButton) submitButton.removeAttribute('disabled');
      $modal.modal('hide');
    });

  $modal.on(`shown.bs.modal${NS}`, function() {
    const nameInput = modal.querySelector('#protocol_name');
    if (nameInput) {
      if (nameInput.parentElement) nameInput.parentElement.classList.remove('error');
      nameInput.value = '';
    }
    const trigger = document.querySelector(`a[data-target="${MODAL}"]`);
    const protocolName = trigger ? trigger.getAttribute('data-protocol-name') : null;
    modal.querySelectorAll('.sci-input-field').forEach((el) => {
      if (protocolName) el.value = protocolName;
    });
    const focusTarget = nameInput || modal.querySelector('.sci-input-field');
    if (focusTarget) focusTarget.focus();
  });
});

onBeforeUnmount(() => {
  if ($modal) {
    $modal.off(NS);
    $modal = null;
  }
});
</script>
