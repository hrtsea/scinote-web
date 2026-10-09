<script setup>
import { onMounted } from 'vue';

// 1:1 port of app/assets/javascripts/assets/office_form.js.
// Original behavior: create the office_frame iframe, attach it to #frameholder,
// then submit #office_form (which targets the iframe by its `name` attribute
// via the form's `target='office_frame'`). The POST response renders inside the
// iframe (Office Online viewer). The form + #frameholder are rendered statically
// by the ERB shell; this component only reproduces the imperative DOM steps that
// the old Sprockets script performed on load.
//
// Note: under Turbolinks a Vue island may mount more than once across
// cache/restore cycles. To avoid stacking duplicate iframes we remove any
// pre-existing #office_frame before recreating it. On a normal (fresh) load this
// is a no-op and the resulting DOM matches the original exactly.
onMounted(() => {
  const existing = document.getElementById('office_frame');
  if (existing) existing.remove();

  const frameholder = document.getElementById('frameholder');
  const officeFrame = document.createElement('iframe');
  officeFrame.name = 'office_frame';
  officeFrame.id = 'office_frame';
  // The title should be set for accessibility
  officeFrame.title = 'Office Online Frame';
  // This attribute allows true fullscreen mode in slideshow view
  // when using PowerPoint Online's 'view' action.
  officeFrame.setAttribute('allowfullscreen', 'true');
  // The sandbox attribute is needed to allow automatic redirection to the O365
  // sign-in page in the business user flow
  officeFrame.setAttribute('sandbox',
    'allow-scripts allow-same-origin allow-forms allow-popups allow-top-navigation allow-popups-to-escape-sandbox');
  frameholder.appendChild(officeFrame);
  document.getElementById('office_form').submit();
});
</script>

<template>
</template>
