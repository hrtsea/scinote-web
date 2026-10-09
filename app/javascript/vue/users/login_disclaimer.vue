<template>
  <div ref="modalEl" class="modal" id="loginDisclaimerModal" tabindex="-1" role="dialog"
       aria-labelledby="loginDisclaimerModalLabel">
    <div class="modal-dialog" role="document">
      <div class="modal-content">
        <div class="modal-header">
          <button type="button" class="close" data-dismiss="modal" aria-label="Close" @click="close">
            <i class="sn-icon sn-icon-close"></i>
          </button>
          <h4 class="modal-title" id="loginDisclaimerModalLabel" v-html="title"></h4>
        </div>
        <div class="modal-body" v-html="body"></div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" @click="close">{{ cancelLabel }}</button>
          <button type="button" class="btn btn-primary" data-action="submit" @click="accept">
            {{ actionLabel }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import $ from 'jquery';

const props = defineProps({
  pairs: { type: Array, default: () => [] },
  title: { type: String, default: '' },
  body: { type: String, default: '' },
  actionLabel: { type: String, default: '' },
  cancelLabel: { type: String, default: '' }
});

const modalEl = ref(null);
let pendingForm = null;
const bound = [];

function open(formSelector) {
  pendingForm = formSelector;
  if (modalEl.value) $(modalEl.value).modal('show');
}

function close() {
  pendingForm = null;
  if (modalEl.value) $(modalEl.value).modal('hide');
}

function accept() {
  const form = pendingForm && document.querySelector(pendingForm);
  if (form) $(form).submit();
  close();
}

onMounted(() => {
  props.pairs.forEach((pair) => {
    if (!pair || !pair.button || !pair.form) return;
    document.querySelectorAll(pair.button).forEach((el) => {
      const handler = (e) => {
        e.preventDefault();
        open(pair.form);
      };
      el.addEventListener('click', handler);
      bound.push([el, handler]);
    });
  });
});

onBeforeUnmount(() => {
  bound.forEach(([el, handler]) => el.removeEventListener('click', handler));
  bound.length = 0;
});
</script>
