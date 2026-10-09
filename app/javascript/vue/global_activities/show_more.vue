<script setup>
// 「加载更多活动」按钮。
// 原 Gen-1（index.js initShowMoreButton）行为：读取全局 globalActivities.getFilters()，
// 带上 page 参数 POST 到 .ga-activities-list 的 data-activities-url，返回 JSON 后把
// activities_html 追加进列表（同日合并），并更新/隐藏按钮。这里 1:1 复刻。
// 列表本体由服务端渲染（global_activities/_activity_list），本组件只负责「更多」交互。
import { getCurrentInstance, ref } from 'vue';

const props = defineProps({
  nextPage: { type: [Number, String, null], default: null },
});

const { appContext } = getCurrentInstance();
const i18n = appContext.config.globalProperties.i18n;

const nextPage = ref(props.nextPage);

function jQuery() {
  return window.jQuery;
}

function animateSpinner(el, start) {
  if (window.animateSpinner) window.animateSpinner(el, start);
}

function loadMore(ev) {
  ev.preventDefault();
  const $ = jQuery();
  if (!$ || !window.globalActivities) return;

  const filters = window.globalActivities.getFilters();
  animateSpinner(null, true);
  filters.page = nextPage.value;

  $.ajax({
    url: $('.ga-activities-list').data('activities-url'),
    data: filters,
    dataType: 'json',
    type: 'POST',
    success(json) {
      let newFirstDay;
      let existingLastDay;

      $('#ga-more-activities-placeholder').append($(json.activities_html));

      newFirstDay = $('#ga-more-activities-placeholder').find('.activities-day').first();
      existingLastDay = $('.ga-activities-list').find('.activities-day').last();

      if (newFirstDay.data('date') === existingLastDay.data('date')) {
        let newNumber;
        existingLastDay.find('.activities-group').append(newFirstDay.find('.activities-group').html());
        newNumber = existingLastDay.find('.activity-card').length;
        existingLastDay.find('.activities-counter-label strong').text(newNumber);
        newFirstDay.remove();
      }

      $('.ga-activities-list').append($('#ga-more-activities-placeholder').html());
      $('#ga-more-activities-placeholder').html('');

      if (json.next_page) {
        nextPage.value = json.next_page;
      } else {
        nextPage.value = null;
      }
      animateSpinner(null, false);
    },
  });
}
</script>

<template>
  <a
    class="btn btn-secondary btn-more-activities"
    :class="{ hidden: !nextPage }"
    :data-next-page="nextPage"
    @click="loadMore"
  >
    {{ i18n.t('activities.index.more_activities') }}
  </a>
</template>
