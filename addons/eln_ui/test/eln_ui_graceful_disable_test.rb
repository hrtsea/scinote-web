# frozen_string_literal: true
#
# ELN UI —— 优雅禁用契约守卫（ADR-0022 §决策1）
#
# ## 守的是什么
# ADR-0022 承诺：addon 的启用/禁用**只由 Gemfile 一行决定**——
#   注释掉 `gem 'scinote_eln_ui'` ⇒ 引擎不被 Bundler 加载 ⇒ routes initializer 不运行
#   ⇒ 路由未注册 ⇒ **宿主照常启动**，仅该 addon 的路径 404（而非 500 / 启动崩溃）。
#
# 这条保证在迁移前是**破的**：30 条路由寄生在宿主 config/routes.rb，
# 注释 Gemfile 后它们会指向一个不再被加载的 controller。
#
# ## 为什么这里只做静态断言，真正的禁用实验要人工跑
# 禁用实验必须改 Gemfile + `bundle install --local` + 重启容器，是**有副作用的操作**，
# 不适合放进每次都跑的单测。已实测过一次（2026-10-12）并记录结果，见文件末尾「实测记录」。
# 本文件守的是**能静态判定的部分**——它保证禁用实验的前提永远成立；
# 若哪天有人把路由挂回宿主，本文件先变红，禁用实验也就失去意义（不再需要跑）。
#
# 2026-10-12 实测记录（容器 scinote_web_production）：
#   · 注释 Gemfile 行 + `bundle install --local` + 重启 ⇒ 宿主启动成功（HTTP 200），零崩溃日志。
#   · eln_ui 全部路径 ⇒ **404**（项目详情 / 项目列表 / 资源中心 / 通知 / 审批人 / 孤儿 V1 / 资源中心网格）。
#   · 同期发现（**独立于路由迁移的既有问题**）：`/eln_workbench` 返回 500，
#     因为 `workbench_payload.rb` 直接调用 `::Scinote::ElnUi::*` 三处
#     （NotificationsPayload / ProjectListScope / ResourceApplication）
#     ⇒ workbench 在役却硬依赖 eln_ui。详见 ADR-0044 §遗留问题。
#   · 🔧 已解决（2026-10-12，ADR-0045）：workbench 整体并入 eln_ui（后端 controller/payload/
#     视图/路由 + 资产登记全部迁到 eln_ui），跨 addon 硬依赖消失。此后禁用 eln_ui 会**连同**
#     `/eln_workbench` 一起 404，契约恢复一致（不再出现"eln_ui 禁了但 workbench 500"）。
#   · 还原后 Gemfile md5 与禁用前一致、全部端点 200 ⇒ 过程幂等、无残留状态。

require_relative 'test_helper'

class ElnUiGracefulDisableTest < AcTest::Base
  HOST_ROUTES_PATH = Rails.root.join('config/routes.rb')
  ELN_UI_ROUTES_PATH = Rails.root.join('addons/eln_ui/config/routes.rb')

  def test_eln_ui_declares_its_own_routes
    assert File.exist?(ELN_UI_ROUTES_PATH),
           'ELN UI 必须有自己的 config/routes.rb —— 否则禁用 Gemfile 行后宿主会残留指向空 controller 的路由'
  end

  def test_host_routes_file_has_no_eln_ui_routes
    # 禁用契约的**前提**：宿主不得残留 ELN UI 路由。
    # 若这条红了，说明路由又被挂回宿主了 ⇒ 优雅禁用重新失效。
    offenders = File.read(HOST_ROUTES_PATH).lines.each_with_index.filter_map do |line, idx|
      next if line.strip.start_with?('#')
      "#{idx + 1}: #{line.strip}" if line =~ %r{to:\s*['"]/?scinote/eln_ui/}
    end

    assert_empty offenders,
                 "宿主 config/routes.rb 残留 ELN UI 路由 #{offenders.size} 处，" \
                 '注释 Gemfile 行后这些路由会指向不再被加载的 controller ⇒ 优雅禁用失效'
  end

  def test_eln_ui_engine_has_routes_initializer
    engine = Rails.root.join('addons/eln_ui/lib/scinote/eln_ui/engine.rb').read

    assert_match(/initializer ['\"]scinote_eln_ui\.routes/, engine,
                 'ELN UI engine 必须有 routes initializer，否则禁用 Gemfile 行时路由不会随之消失')
    assert_match(/after:\s*:add_routes/, engine,
                 'routes initializer 应显式声明 after: :add_routes（ADR-0022 §决策4）')
    assert_match(/app\.routes\.append/, engine,
                 '必须用 append（而非 prepend）挂载 —— prepend 会让 addon 覆盖核心路由，破坏 ADR-0022 的安全取舍')
  end

  def test_gemfile_registers_eln_ui_with_path_source
    gemfile = Rails.root.join('Gemfile').read
    line = gemfile.lines.find { |l| l =~ /^\s*gem ['"]scinote_eln_ui['"]/ }

    refute_nil line,
              "Gemfile 应以 ^gem 'scinote_eln_ui' 注册（不可缩进/不可注释），" \
              '禁用与启用都靠这一行 —— 它是契约的唯一开关'
    assert_match %r{path:\s*['"]addons/eln_ui['"]}, line,
                 '必须用 path: addons/eln_ui（gem 名双下划线、目录名单段，见 addons-host-contract §3）'
  end
end