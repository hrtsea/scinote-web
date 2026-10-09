<script setup>
import { onMounted, onBeforeUnmount } from 'vue';

// Gen-1 asset: app/assets/javascripts/shareable_links/my_module_results_show.js
// Behavioral port only. The results markup (result cards, tables, comments
// sidebars, file-preview modals) is server-rendered by the shareable_links
// partials and is left untouched. We only re-bind the same document-delegated
// handlers + handsontable init against that existing DOM.
//
// Note on handsontable: these read-only shareable pages render plain HTML
// tables via `protocols/table_element` (no `.hot-table-container` is emitted
// by any ERB here), so `initializeHandsonTable` is effectively a no-op, exactly
// as in the legacy asset. `handsontable.full` is still kept in the ERB and the
// global `Handsontable` / `$.fn.handsontable` is reused (handsontable is NOT a
// npm dependency in this project — see package.json).

const $ = window.jQuery;
const NAMESPACE = 'shareableResultsShow';

let hotElements = [];

function initializeHandsonTable(el) {
  const input = $(el).siblings('input.hot-table-contents');
  const inputObj = JSON.parse(input.attr('value'));
  const data = inputObj.data;
  const metadata = JSON.parse($(el).siblings('input.hot-table-metadata').val() || '{}');

  $(el).handsontable({
    disableVisualSelection: true,
    rowHeaders: true,
    colHeaders: true,
    editor: false,
    copyPaste: false,
    formulas: true,
    data,
    cell: metadata.cells || []
  });
  hotElements.push(el);
}

function destroyHandsontable() {
  hotElements.forEach((el) => {
    try {
      $(el).handsontable('destroy');
    } catch (e) {
      // element may already be detached by a Turbolinks cache snapshot
    }
  });
  hotElements = [];
}

function initAttachments() {
  $(document).on(
    `click.${NAMESPACE}`,
    '.shareable-file-preview-link, .shareable-gallery-switcher',
    function (e) {
      e.preventDefault();
      $('.modal-file-preview.in').modal('hide');
      $($(`.modal-file-preview[data-object-id=${$(this).data('id')}]`)).modal('show');
    }
  );
}

function initResultComments() {
  $(document).on(`click.${NAMESPACE}`, '.shareable-link-open-comments-sidebar', function (e) {
    e.preventDefault();
    $('.comments-sidebar').removeClass('open');
    $($(this).data('objectTarget')).addClass('open');
  });
}

function initResultsExpandCollapse() {
  $(document).on(`click.${NAMESPACE}`, '#results-collapse-btn', () => {
    $('.result-container .collapse').collapse('hide');
  });
  $(document).on(`click.${NAMESPACE}`, '#results-expand-btn', () => {
    $('.result-container .collapse').collapse('show');
  });
}

onMounted(() => {
  initAttachments();
  initResultsExpandCollapse();
  initResultComments();

  $('.hot-table-container').each(function () {
    initializeHandsonTable(this);
  });
});

onBeforeUnmount(() => {
  $(document).off(`.${NAMESPACE}`);
  destroyHandsontable();
});
</script>

<template>
  <!--
    Controller island: no markup is rendered here. The result cards / comments
    sidebars / file-preview modals are server-rendered by shareable_links
    partials; this component only re-attaches the delegated click handlers and
    handsontable init that the legacy Gen-1 asset provided. The sort dropdown
    and kaminari pagination are plain server-rendered links (no JS needed).
  -->
</template>
