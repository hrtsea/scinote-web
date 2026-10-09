<template>
  <Teleport to="#reportsNewHeaderMount">
    <div class="reports-new-header">
      <div class="sci-input-container report-name-container">
        <input
          ref="nameInput"
          v-model="reportName"
          type="text"
          class="sci-input-field report-name"
          :placeholder="i18nStrings.report_name_placeholder"
          data-e2e="e2e-IF-reports-wizard-title"
        />
      </div>
      <button
        class="btn btn-secondary cancel-button"
        data-toggle="modal"
        data-target="#reportWizardExitWarning"
        data-e2e="e2e-BT-reports-wizard-cancel"
      >
        {{ i18nStrings.cancel }}
      </button>
    </div>
  </Teleport>

  <Teleport to="#reportsNewFooterMount">
    <div class="reports-new-footer" :data-step="currentStep">
      <div class="back-container">
        <button
          class="btn btn-secondary back-button"
          data-e2e="e2e-BT-reports-wizard-back"
          @click="prevStep"
        >
          {{ i18nStrings.back }}
        </button>
      </div>

      <div class="wizard-status">
        <div class="progress-line progress-step-1"></div>
        <div class="progress-line progress-step-2"></div>
        <div
          v-for="i in 3"
          :key="i"
          class="wizard-steps"
          :class="`wizard-step-${i}`"
        >
          <div class="step-id">{{ i }}</div><br>
          <div class="step-dot"></div><br>
          <div class="step-name">
            <span class="name-wrapper">{{ i18nStrings[`step_${i}`] }}</span>
          </div>
          <div
            v-if="enableChangeStep"
            class="change-step"
            :data-step-id="i"
            @click="goToStep(i)"
          ></div>
        </div>
      </div>

      <div class="next-button-container">
        <button
          class="btn btn-primary continue-button"
          :disabled="!canContinue"
          data-e2e="e2e-BT-reports-wizard-continue"
          @click="nextStep"
        >
          {{ i18nStrings.continue_button }}
        </button>

        <div v-if="edit" class="report-generate-actions-dropdown sci-dropdown dropup">
          <button
            id="reportGenerateMenu"
            class="btn btn-primary dropdown-toggle single-object-action"
            type="button"
            data-toggle="dropdown"
            aria-haspopup="true"
            aria-expanded="true"
          >
            {{ i18nStrings.generate_as_button }}
            <span class="caret pull-right"></span>
          </button>
          <ul
            id="reportGenerateMenuDropdown"
            class="dropdown-menu dropdown-menu-right"
            aria-labelledby="reportGenerateMenu"
          >
            <li>
              <a
                id="saveAsNewReport"
                href="#"
                :class="{ disabled: !canGenerate }"
                @click.prevent="saveAsNew"
              >
                <i class="sn-icon sn-icon-new-task-circle"></i>
                {{ i18nStrings.save_as_new_report }}
              </a>
            </li>
            <li>
              <a
                id="UpdateReport"
                href="#"
                :class="{ disabled: !canGenerate }"
                @click.prevent="updateReport"
              >
                <i class="fas fa-redo-alt"></i>
                {{ i18nStrings.update_report }}
              </a>
            </li>
          </ul>
        </div>
        <button
          v-else
          class="btn btn-primary generate-button"
          :disabled="!canGenerate"
          data-e2e="e2e-BT-reports-wizard-generate"
          @click="generate"
        >
          {{ i18nStrings.generate_button }}
        </button>
      </div>
    </div>
  </Teleport>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';

const { $, dropdownSelector, animateSpinner, HelperModule, GLOBAL_CONSTANTS } = window;

const props = defineProps({
  reportName: { type: String, default: '' },
  edit: { type: Boolean, default: false },
  enableChangeStep: { type: Boolean, default: false },
  createUrl: { type: String, default: '' },
  updateUrl: { type: String, default: '' },
  nameMinLength: { type: Number, default: 2 },
  i18nStrings: { type: Object, default: () => ({}) }
});

const root = () => document.querySelector('.reports-new');

const nameInput = ref(null);
const currentStep = ref(1);
const reportName = ref(props.reportName);
const canContinue = ref(false);
const canGenerate = ref(false);
const busy = ref(false);

/**
 * Read a value out of the server-rendered panes. The three wizard panes stay
 * server-rendered (they carry a lot of Rails-side permission/scope logic), so
 * Vue owns state and reaches into them by selector.
 */
const q = (sel) => root()?.querySelector(sel);
const qa = (sel) => Array.from(root()?.querySelectorAll(sel) || []);

function getSelectedRepositoryColumnValues(element, selectedAll = false) {
  if (!element) return [];
  return Array.from(element.querySelectorAll('option'))
    .filter((option) => option.getAttribute('selected-value') || selectedAll)
    .map((option) => option.value);
}

function allCheckboxesSelected(container) {
  if (!container) return false;
  const checked = container.querySelectorAll('.sci-checkbox:not(.skip-select-all):checked').length;
  const all = container.querySelectorAll('.sci-checkbox:not(.skip-select-all)').length;
  return checked === all;
}

/* ---------------------------------------------------------------- step nav */

function goToStep(step) {
  const next = Math.min(3, Math.max(1, step));
  currentStep.value = next;

  qa('.reports-new-body .tab-pane').forEach((el) => el.classList.remove('active'));
  const pane = q(`#new-report-step-${next}`);
  if (pane) pane.classList.add('active');

  const footer = q('.reports-new-footer');
  if (footer) footer.setAttribute('data-step', String(next));

  if (next === 2) loadProjectContents();
  if (next === 3) syncStepThreeDefaults();

  validateGenerateButtons();
}

const nextStep = () => goToStep(currentStep.value + 1);
const prevStep = () => goToStep(currentStep.value - 1);

/* ------------------------------------------------------------ data payload */

function getReportData() {
  const reportData = {
    report: {
      name: reportName.value,
      description: q('#projectDescription')?.value || '',
      settings: { task: { protocol: {} } }
    },
    project_id: dropdownSelector.getValues('#projectSelector'),
    template_values: {}
  };

  qa('.report-template-values-container .sci-input-field:not(.report-template-value-dropdown)')
    .forEach((field) => {
      if (field.value.length === 0) return;
      reportData.template_values[field.name] = {
        value: field.value,
        view_component: field.dataset.type
      };
    });

  qa('.report-template-values-container select').forEach((field) => {
    const values = dropdownSelector.getValues(field);
    if (!values || values.length === 0) return;
    reportData.template_values[field.name] = {
      value: values,
      view_component: field.dataset.type
    };
  });

  qa('.report-template-values-container .sci-checkbox').forEach((checkbox) => {
    if (checkbox.name.includes('[]')) {
      const name = checkbox.name.replace('[]', '');
      if (!reportData.template_values[name]) {
        reportData.template_values[name] = { value: {}, view_component: checkbox.dataset.type };
      }
      reportData.template_values[name].value[checkbox.value] = checkbox.checked;
    } else {
      reportData.template_values[checkbox.name] = {
        value: checkbox.checked,
        view_component: checkbox.dataset.type
      };
    }
  });

  reportData.project_content = { experiments: [] };
  qa('.project-contents-container .experiment-element').forEach((experiment) => {
    const expCheckbox = experiment.querySelector('.report-experiment-checkbox');
    if (!expCheckbox.checked && !expCheckbox.indeterminate) return;

    const experimentData = {
      id: parseInt(expCheckbox.value, 10),
      my_module_ids: []
    };
    experiment.querySelectorAll('.report-my-module-checkbox:checked').forEach((myModule) => {
      experimentData.my_module_ids.push(parseInt(myModule.value, 10));
    });
    reportData.project_content.experiments.push(experimentData);
  });

  const settings = reportData.report.settings;
  settings.template = dropdownSelector.getValues('#templateSelector');
  settings.docx_template = dropdownSelector.getValues('#docxTemplateSelector');
  settings.all_tasks = !!q('.project-contents-container .select-all-my-modules-checkbox')?.checked;

  qa('.task-contents-container .content-element .protocol-setting').forEach((e) => {
    settings.task.protocol[e.value] = e.checked;
  });
  qa('.task-contents-container .content-element .task-setting').forEach((e) => {
    settings.task[e.value] = e.checked;
  });

  settings.task.repositories = [];
  settings.task.excluded_repository_columns = {};
  qa('.task-contents-container .repositories-contents .repositories-setting:checked').forEach((e) => {
    const value = parseInt(e.value, 10);
    const column = e.closest('.flex')?.querySelector('.repository-columns');
    if (!column) return;

    const selectedValues = dropdownSelector.getValues(column);
    const excludedValues = getSelectedRepositoryColumnValues(column, true)
      .filter((item) => !selectedValues.includes(item))
      .map((item) => parseInt(item, 10));

    settings.task.repositories.push(value);
    settings.task.excluded_repository_columns[value] = excludedValues;
  });

  settings.task.result_order = dropdownSelector.getValues('#taskResultsOrder');
  settings.exclude_task_metadata = !!q('.exclude-task-metadata-setting')?.checked;
  settings.exclude_timestamps = !!q('.exclude-timestamps-setting')?.checked;
  settings.report_info_metadata = !!q('.report-info-metadata-setting')?.checked;

  return reportData;
}

/* ------------------------------------------------------------- validation */

function validateGenerateButtons() {
  const validName = reportName.value.length >= props.nameMinLength;
  const validContent = getReportData().project_content.experiments.length > 0;
  canGenerate.value = validName && validContent;
}

function reCheckContinueButton() {
  const docxHidden = !!q('#docxTemplateSelector')?.closest('.hidden');
  const ok = dropdownSelector.getValues('#projectSelector').length > 0
    && dropdownSelector.getValues('#templateSelector').length > 0
    && (dropdownSelector.getValues('#docxTemplateSelector').length > 0 || docxHidden);
  canContinue.value = ok;
}

function syncStepThreeDefaults() {
  const protocolSteps = q('.task-contents-container .protocol-steps-checkbox');
  const allResults = q('.task-contents-container .all-results-checkbox');
  const allTaskContents = q('.task-contents-container .select-all-task-contents');

  if (protocolSteps) protocolSteps.checked = allCheckboxesSelected(q('.report-protocol-settings'));
  if (allResults) allResults.checked = allCheckboxesSelected(q('.report-result-settings'));
  if (allTaskContents) allTaskContents.checked = allCheckboxesSelected(q('.report-task-settings'));
}

/* ------------------------------------------------------------------ submit */

function submitReport(url, type) {
  if (!canGenerate.value || busy.value) return;
  busy.value = true;

  $.ajax({
    url,
    type,
    data: JSON.stringify(getReportData()),
    contentType: 'application/json; charset=utf-8',
    complete: () => { busy.value = false; },
    error: (jqxhr) => {
      HelperModule.flashAlertMsg(jqxhr.responseJSON.join(' '), 'danger');
    }
  });
}

const generate = () => submitReport(props.createUrl, 'POST');
const saveAsNew = () => submitReport(props.createUrl, 'POST');
const updateReport = () => submitReport(props.updateUrl, 'PUT');

/* --------------------------------------------------------------- AJAX loads */

function loadProjectContents() {
  const projectContents = q('#new-report-step-2 .project-contents');
  if (!projectContents) return;

  const projectId = dropdownSelector.getValues('#projectSelector');
  if (parseInt(projectContents.getAttribute('data-project-id'), 10) === parseInt(projectId, 10)) return;

  animateSpinner('.reports-new-body');
  $.get(projectContents.dataset.projectContentUrl, { project_id: projectId }, (data) => {
    animateSpinner('.reports-new-body', false);
    projectContents.setAttribute('data-project-id', projectId);
    projectContents.innerHTML = data.html;

    const selectAll = q('.select-all-my-modules-checkbox');
    if (selectAll?.checked) selectAll.dispatchEvent(new Event('change', { bubbles: true }));

    $('.experiment-contents').sortable();
  });
}

function loadTemplate({ selector, container, path }) {
  const template = dropdownSelector.getValues(selector);
  const el = q(selector);
  if (!el) return;

  el.dataset.selectedTemplate = template;
  $.get(path, { project_id: dropdownSelector.getValues('#projectSelector'), template }, (result) => {
    const box = q(container);
    if (!box) return;
    box.classList.remove('hidden');
    box.innerHTML = result.html;

    $('.section').each((_, section) => {
      const collapseButton = $(section).find('.sn-icon-down');
      const valuesContainer = $(section).find('.values-container');
      if (valuesContainer.children().length === 0) collapseButton.hide();
    });

    $(box).find('.report-template-value-dropdown').each((_, dropdown) => {
      dropdownSelector.init($(dropdown), { noEmptyOption: true });
    });
  });
}

const loadPdfTemplate = () => loadTemplate({
  selector: '#templateSelector',
  container: '.report-template-values-container.pdf',
  path: q('#templateSelector')?.dataset.valuesEditorPath
});

const loadDocxTemplate = () => loadTemplate({
  selector: '#docxTemplateSelector',
  container: '.report-template-values-container.docx',
  path: q('#docxTemplateSelector')?.dataset.valuesEditorPath
});

/* ------------------------------------------------------ delegated listeners */

function onProjectContentsChange(event) {
  const target = event.target;
  if (!target.classList.contains('sci-checkbox')) return;

  const container = q('.project-contents-container');

  if (target.classList.contains('report-experiment-checkbox')) {
    target.closest('li').querySelectorAll('.report-my-module-checkbox').forEach((box) => {
      box.checked = target.checked;
      box.indeterminate = false;
    });
  } else if (target.classList.contains('select-all-my-modules-checkbox')) {
    qa('.report-experiment-checkbox, .report-my-module-checkbox').forEach((box) => {
      box.checked = target.checked;
      box.indeterminate = false;
    });
  } else if (target.classList.contains('report-my-module-checkbox')) {
    const experimentElement = target.closest('.experiment-element');
    const experiment = experimentElement.querySelector('.report-experiment-checkbox');
    const all = experimentElement.querySelectorAll('.report-my-module-checkbox').length;
    const checked = experimentElement.querySelectorAll('.report-my-module-checkbox:checked').length;

    experiment.indeterminate = false;
    experiment.checked = all === checked;
    if (all !== checked && checked > 0) experiment.indeterminate = true;
  } else if (target.classList.contains('hide-unchecked-checkbox')) {
    hideUncheckedElements(target.checked);
    return;
  } else {
    return;
  }

  selectAllState();
  hideUncheckedElements(q('.hide-unchecked-checkbox')?.checked);
  if (container) validateGenerateButtons();
}

function hideUncheckedElements(hide) {
  qa('.report-experiment-checkbox, .report-my-module-checkbox').forEach((box) => {
    box.closest('li').style.display = '';
  });
  if (!hide) return;
  qa(`.report-experiment-checkbox:not(:checked):not(:indeterminate),
      .report-my-module-checkbox:not(:checked):not(:indeterminate)`)
    .forEach((box) => { box.closest('li').style.display = 'none'; });
}

function selectAllState() {
  const selectAll = q('.select-all-my-modules-checkbox');
  if (!selectAll) return;
  const all = qa('.report-my-module-checkbox').length;
  const checked = qa('.report-my-module-checkbox:checked').length;

  selectAll.indeterminate = false;
  selectAll.checked = all === checked;
  if (all !== checked && checked > 0) selectAll.indeterminate = true;
}

function onTaskContentsChange(event) {
  const target = event.target;
  if (!target.classList.contains('sci-checkbox')) return;

  const setAll = (selector, all, checked) => {
    const el = q(selector);
    if (!el) return;
    el.indeterminate = false;
    el.checked = all === checked;
    if (all !== checked && checked > 0) el.indeterminate = true;
  };

  if (target.classList.contains('select-all-task-contents')) {
    qa('.content-element .sci-checkbox:not(.skip-select-all)')
      .forEach((box) => { box.checked = target.checked; });
  } else if (target.classList.contains('protocol-steps-checkbox')) {
    qa('.step-contents .sci-checkbox').forEach((box) => { box.checked = target.checked; });
  } else if (target.classList.contains('all-results-checkbox')) {
    qa('.results-type-contents .sci-checkbox:not(.skip-select-all)')
      .forEach((box) => { box.checked = target.checked; });
  } else if (target.classList.contains('select-all-repositories')) {
    qa('.repositories-contents .sci-checkbox').forEach((box) => { box.checked = target.checked; });
  } else if (target.closest('.repositories-contents')) {
    setAll(
      '.task-contents-container .select-all-repositories',
      qa('.repositories-contents .sci-checkbox').length,
      qa('.repositories-contents .sci-checkbox:checked').length
    );
  } else if (target.closest('.step-contents')) {
    setAll(
      '.task-contents-container .protocol-steps-checkbox',
      qa('.step-contents .sci-checkbox').length,
      qa('.step-contents .sci-checkbox:checked').length
    );
  } else if (target.closest('.results-type-contents')) {
    setAll(
      '.task-contents-container .all-results-checkbox',
      qa('.results-type-contents .sci-checkbox:not(.skip-select-all)').length,
      qa('.results-type-contents .sci-checkbox:not(.skip-select-all):checked').length
    );
  } else if (target.closest('.report-task-settings')) {
    setAll(
      '.task-contents-container .select-all-task-contents',
      qa('.report-task-settings .sci-checkbox:not(.skip-select-all)').length,
      qa('.report-task-settings .sci-checkbox:not(.skip-select-all):checked').length
    );
  }
}

function onProjectContentsClick(event) {
  const target = event.target.closest('button, .change-step');
  if (!target) return;

  if (target.classList.contains('move-up')) {
    const experiment = target.closest('.experiment-element');
    experiment?.parentElement?.insertBefore(experiment, experiment.previousElementSibling);
  } else if (target.classList.contains('move-down')) {
    const experiment = target.closest('.experiment-element');
    if (experiment?.nextElementSibling) {
      experiment.parentElement.insertBefore(experiment.nextElementSibling, experiment);
    }
  } else if (target.classList.contains('collapse-all')) {
    $('.experiment-contents').collapse('hide');
  } else if (target.classList.contains('expand-all')) {
    $('.experiment-contents').collapse('show');
  }
}

function onTemplateValuesClick(event) {
  const target = event.target.closest('button');
  if (!target) return;

  if (target.classList.contains('collapse-all')) {
    qa('.report-template-values-container .values-container')
      .forEach((el) => $(el).collapse('hide'));
  } else if (target.classList.contains('expand-all')) {
    qa('.report-template-values-container .values-container')
      .forEach((el) => $(el).collapse('show'));
  }
}

/* ------------------------------------------------------------ init / bridge */

function initDropdowns() {
  dropdownSelector.init('#projectSelector', {
    singleSelect: true,
    closeOnSelect: true,
    noEmptyOption: true,
    selectAppearance: 'simple',
    onSelect: () => {
      const projectId = parseInt(dropdownSelector.getValues('#projectSelector'), 10);
      const loadedId = parseInt(q('#new-report-step-2 .project-contents')?.getAttribute('data-project-id'), 10);
      if (!Number.isNaN(loadedId) && loadedId !== projectId) {
        $('#projectReportWarningModal').modal('show');
      }
      if (dropdownSelector.getValues('#projectSelector').length > 0) {
        dropdownSelector.enableSelector('#templateSelector');
        dropdownSelector.enableSelector('#docxTemplateSelector');
        if (q('#templateSelector')?.dataset.defaultTemplate) {
          dropdownSelector.selectValues('#templateSelector', q('#templateSelector').dataset.defaultTemplate);
        }
        if (q('#docxTemplateSelector')?.dataset.defaultTemplate) {
          dropdownSelector.selectValues('#docxTemplateSelector', q('#docxTemplateSelector').dataset.defaultTemplate);
        }
      } else {
        dropdownSelector.selectValues('#templateSelector', '');
        dropdownSelector.disableSelector('#templateSelector');
        dropdownSelector.selectValues('#docxTemplateSelector', '');
        dropdownSelector.disableSelector('#docxTemplateSelector');
      }
      reCheckContinueButton();
    }
  });

  const templateOnSelect = (selector, container) => () => {
    if (dropdownSelector.getValues(selector).length === 0) {
      const box = q(container);
      if (box) { box.innerHTML = ''; box.classList.add('hidden'); }
      reCheckContinueButton();
      return;
    }

    const filled = Array.from(q(container)?.querySelectorAll('input.sci-input-field, textarea.sci-input-field') || [])
      .filter((field) => !!field.value).length;

    if (filled === 0) {
      if (selector === '#templateSelector') loadPdfTemplate(); else loadDocxTemplate();
    } else {
      $('#templateReportWarningModal').modal('show');
    }
    reCheckContinueButton();
  };

  dropdownSelector.init('#templateSelector', {
    singleSelect: true,
    closeOnSelect: true,
    noEmptyOption: true,
    selectAppearance: 'simple',
    disableSearch: true,
    onSelect: templateOnSelect('#templateSelector', '.report-template-values-container.pdf')
  });

  dropdownSelector.init('#docxTemplateSelector', {
    singleSelect: true,
    closeOnSelect: true,
    noEmptyOption: true,
    selectAppearance: 'simple',
    disableSearch: true,
    onSelect: templateOnSelect('#docxTemplateSelector', '.report-template-values-container.docx')
  });

  if (dropdownSelector.getValues('#templateSelector').length > 0) {
    loadPdfTemplate();
  } else {
    dropdownSelector.disableSelector('#templateSelector');
  }

  if (dropdownSelector.getValues('#docxTemplateSelector').length > 0) {
    loadDocxTemplate();
  } else {
    dropdownSelector.disableSelector('#docxTemplateSelector');
  }

  qa('.repository-columns').forEach((element) => {
    const id = `#${element.id}`;
    const values = getSelectedRepositoryColumnValues(element);
    dropdownSelector.init(id, { selectAppearance: 'simple', optionClass: 'checkbox-icon' });
    if (values.length) dropdownSelector.selectValues(id, values);
  });

  dropdownSelector.init('.task-contents-container .order-results', {
    singleSelect: true,
    closeOnSelect: true,
    noEmptyOption: true,
    selectAppearance: 'simple',
    disableSearch: true
  });
}

const listeners = [];

function bind(selector, type, handler) {
  const el = typeof selector === 'string' ? document.querySelector(selector) : selector;
  if (!el) return;
  el.addEventListener(type, handler);
  listeners.push([el, type, handler]);
}

onMounted(() => {
  nameInput.value?.focus();

  bind('.project-contents-container', 'change', onProjectContentsChange);
  bind('.project-contents-container', 'click', onProjectContentsClick);
  bind('.task-contents-container', 'change', onTaskContentsChange);
  bind('.report-template-values-container', 'click', onTemplateValuesClick);

  // Warning modals stay server-rendered; only their button semantics move here.
  bind('#loadSelectedTemplate', 'click', () => {
    loadPdfTemplate();
    $('#templateReportWarningModal').addClass('skip-hide-event').modal('hide');
  });
  bind('#cancelTemplateChange', 'click', () => {
    $('#templateReportWarningModal').modal('hide');
  });
  bind('#cancelProjectChange', 'click', () => {
    const loadedId = q('#new-report-step-2 .project-contents')?.getAttribute('data-project-id');
    dropdownSelector.selectValues('#projectSelector', loadedId);
    $('#projectReportWarningModal').modal('hide');
  });

  initDropdowns();

  $('.experiment-contents').sortable();
  if (props.edit) $('#reportWizardEditWarning').modal('show');

  goToStep(1);
});

onBeforeUnmount(() => {
  listeners.forEach(([el, type, handler]) => el.removeEventListener(type, handler));
});

defineExpose({ getReportData, goToStep });
</script>
