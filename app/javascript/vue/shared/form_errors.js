// Re-implementation of the Gen-1 jQuery plugin `$.fn.renderFormErrors`
// (app/assets/javascripts/sitewide/form_errors.js) for Vue islands.
//
// These user auth pages only ever call the plugin in its simplest mode:
//   $('form').renderFormErrors('<model>', errors, false)
// i.e. with `clear=false` (never clearFormErrors) and no event object.
// The plugin searches every <form> on the page for inputs named
// `<model>[<field>]`, adds `.has-error` to the closest `.form-group`,
// and appends a `<span class="help-block">MSG.</span>` after the input.
// The first erroneous field is focused.
//
// This module is intentionally framework-free so the migrated pages no
// longer depend on the global Sprockets/jQuery stack for error display.

function strToErrorFormat(str) {
  const s = String(str);
  return s.endsWith('.') ? s.slice(0, -1) : s;
}

function buildErrorText(messages) {
  const arr = Array.isArray(messages) ? messages : [messages];
  const text = arr
    .map((m) => {
      const inner = Array.isArray(m) ? m.join(', ') : m;
      return strToErrorFormat(inner);
    })
    .join('<br />');
  return `${text}.`;
}

function findInputs(forms, modelName, field) {
  // Mirrors: new RegExp(modelName + '\\[' + field + '\\(?\')
  const regex = new RegExp(modelName + '\\[' + field + '\\(?');
  const inputs = [];
  forms.forEach((form) => {
    form.querySelectorAll('input, file, select, textarea').forEach((el) => {
      const name = el.getAttribute('name');
      if (name && name.match(regex)) inputs.push(el);
    });
  });
  return inputs;
}

export function applyFormErrors(forms, errorSets) {
  if (!forms || !forms.length) return;
  let focused = false;

  errorSets.forEach(({ modelName, errors }) => {
    if (!errors) return;
    Object.keys(errors).forEach((field) => {
      const messages = errors[field];
      const inputs = findInputs(forms, modelName, field);
      inputs.forEach((input) => {
        const formGroup = input.closest('.form-group');
        if (formGroup && !formGroup.classList.contains('has-error')) {
          formGroup.classList.add('has-error');
        }

        const span = document.createElement('span');
        span.className = 'help-block';
        span.innerHTML = buildErrorText(messages);
        input.insertAdjacentElement('afterend', span);

        // Focus the first erroneous field (matches the original:
        // goToFormElement fires only when the form reaches exactly
        // one .has-error group).
        if (!focused) {
          const form = input.closest('form');
          if (form && form.querySelectorAll('.form-group.has-error').length === 1) {
            input.focus();
            focused = true;
          }
        }
      });
    });
  });
}
