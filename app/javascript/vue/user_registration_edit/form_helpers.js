// Shared helpers for the user registration edit forms.
// These replicate the Gen-1 behavior that used to live in
// app/assets/javascripts/users/registrations/edit.js:
//   - inline view/edit toggle (now driven declaratively by Vue)
//   - ajax PUT submit to the `format: :json` registration endpoint
//   - inline error rendering equivalent to $.fn.renderFormErrors('user', ...)

export function getCsrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.content : '';
}

export function clearFormErrors(formEl) {
  if (!formEl) return;
  formEl.querySelectorAll('.help-block').forEach((el) => el.remove());
  formEl.querySelectorAll('.form-group.has-error').forEach((el) => el.classList.remove('has-error'));
}

// Mirrors app/assets/javascripts/sitewide/form_errors.js `renderFormError`
// for the non-modal, non-tab case: mark the .form-group as has-error and
// append a <span class="help-block">message.</span> after the input.
export function showFormErrors(formEl, errorData) {
  clearFormErrors(formEl);
  if (!formEl) return;
  let firstErrorInput = null;
  Object.entries(errorData || {}).forEach(([field, messages]) => {
    const inputs = Array.from(formEl.querySelectorAll('input, select, textarea')).filter((el) => {
      const name = el.getAttribute('name');
      return name && name.match(new RegExp(`user\\[${field}\\(?`));
    });
    inputs.forEach((el) => {
      const group = el.closest('.form-group');
      if (group && !group.classList.contains('has-error')) group.classList.add('has-error');
      const text = Array.isArray(messages) ? messages.join(', ') : String(messages);
      const span = document.createElement('span');
      span.className = 'help-block';
      span.textContent = `${text}.`;
      el.after(span);
      if (!firstErrorInput) firstErrorInput = el;
    });
  });
  if (firstErrorInput) {
    firstErrorInput.focus();
    firstErrorInput.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
}

// Submit the form via fetch (PUT) to the JSON endpoint, exactly like the
// previous jQuery-ujs `remote: true` form. On success the page reloads
// (original handler did `location.reload()`); on error we render inline.
export async function submitRegistrationForm(formEl, url, csrfToken) {
  const body = new FormData(formEl);
  const response = await fetch(url, {
    method: 'PUT',
    body,
    headers: {
      'X-CSRF-Token': csrfToken,
      Accept: 'application/json',
    },
    credentials: 'same-origin',
  });
  if (response.ok) {
    window.location.reload();
    return { ok: true };
  }
  const data = await response.json().catch(() => ({}));
  return { ok: false, errors: data };
}
