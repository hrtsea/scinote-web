# frozen_string_literal: true
#
# ELN UI —— ResGrid 自适应高度守卫（轻量静态漂移检查，不依赖 DB / Rails）
#
# ## 守的是什么（见 ADR-0047）
# eln_ui 内嵌 12 张 AG Grid 表（ProjectDetail 7 + ResCenter 5）经 `ResGrid.vue` 薄封装复用
# 宿主 `shared/datatable/table.vue`。诉求：**表格按当前页行数自适应，无表格内部独立纵向滚动条**
# （移动端同样友好）。
#
# 实现 = 宿主 opt-in `autoHeight` prop + AG Grid 原生 `domLayout:'autoHeight'`，
# `ResGrid` 透传 `:auto-height="!height"`。默认关 ⇒ 原生 /projects 等全站表格零影响。
#
# ## 为什么需要静态守卫
# 真机验证靠「重建 webpack entry + 重签 Warden 会话 + Playwright 量化滚动条」，成本高、
# 不在每次 CI 跑。这条静态测试守三件容易被无声回退的事：
#   1. 宿主 `table.vue` 的三处接线（prop / domLayout / 条件类）被谁删掉 ⇒ autoHeight 静默失效；
#   2. `ResGrid.vue` 被改回「手算行数×40」旧方案（该方案真机已证伪：AG Grid 内部高度
#      分解与手算不匹配，`.ag-body-viewport` 只有 49px 而内容 120px，内部滚动条复现）；
#   3. 某张表又被加回显式 `height=` ⇒ 该表退回固定高度 + 内部滚动。
#
# 运行期口径（可选，仅服务进程内有效）：宿主 `table.vue` 的 `autoHeight` 默认值可通过
# `components` 查，但 RAILS_ENV=test 下 addon 的 Engine.routes 为 0 条、且前端组件未挂载，
# 故本守卫只做静态漂移检查（与 addon_settings helper 转发守卫同一模式）。

require 'minitest/autorun'

class ElnUiResgridAutoheightTest < Minitest::Test
  RESGRID_VUE = File.expand_path('../app/javascript/vue/eln/views/ResGrid.vue', __dir__).freeze
  PROJECT_DETAIL_VUE = File.expand_path('../app/javascript/vue/eln/views/ProjectDetail.vue', __dir__).freeze
  RES_CENTER_VUE = File.expand_path('../app/javascript/vue/eln/views/ResCenter.vue', __dir__).freeze
  HOST_TABLE_VUE = File.expand_path('../../../app/javascript/vue/shared/datatable/table.vue', __dir__).freeze

  def test_resgrid_passes_auto_height_through
    src = File.read(RESGRID_VUE)
    assert_includes(src, ':auto-height="!height"',
                    'ResGrid.vue 必须透传 :auto-height="!height" 给宿主 DataTable')
  end

  def test_resgrid_keeps_height_override_knob
    src = File.read(RESGRID_VUE)
    assert_match(/height:\s*\{\s*type:\s*String,\s*default:\s*null\s*\}/, src,
                 'ResGrid.vue 必须保留 height prop（default: null）作个别长表的 override 旋钮（Q4=B）')
  end

  def test_resgrid_has_no_manual_row_height_math
    src = File.read(RESGRID_VUE)
    refute_includes(src, 'effectiveHeight',
                    '「手算行数×40 + 表头 + 缓冲」旧方案已真机证伪，不得回退（见 ADR-0047）')
    refute_includes(src, 'GRID_ROW_H',
                    '固定 40px 行高假设已废弃，不得回退（行高变化由 AG Grid autoHeight 自行处理）')
    refute_includes(src, 'rowCount.value =',
                    '不得再按 @table-reloaded 行数推算容器高度')
  end

  def test_host_table_vue_wires_autoheight_prop
    src = File.read(HOST_TABLE_VUE)
    assert_match(/autoHeight:\s*\{\s*type:\s*Boolean,\s*default:\s*false\s*\}/, src,
                 '宿主 table.vue 必须有 autoHeight prop 且默认 false（opt-in，原生 /projects 零影响）')
    assert_includes(src, "domLayout: this.autoHeight ? 'autoHeight' : 'normal'",
                    '宿主 gridOptions 必须按 autoHeight 切换 domLayout')
    assert_includes(src, "'flex-grow h-full': !autoHeight",
                    'autoHeight 开启时不得施加固定高度类（否则 AG Grid 无法自行撑开）')
  end

  def test_no_resgrid_callsite_passes_explicit_height
    [PROJECT_DETAIL_VUE, RES_CENTER_VUE].each do |file|
      src = File.read(file)
      tags = src.scan(/<ResGrid\b[^>]*>/)
      refute_empty(tags, "#{File.basename(file)} 中未找到 <ResGrid> 调用点")

      tags.each do |tag|
        table_id = tag[/table-id="([^"]+)"/, 1]
        refute_match(/(:|\b)height\s*=/, tag,
                     "#{File.basename(file)} 的 #{table_id} 不得传显式 height（应走默认 autoHeight）")
      end
    end
  end
end
