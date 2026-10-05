# frozen_string_literal: true
#
# ELN UI —— 任务详情页（PAGE-TASK-DETAIL）
#
# 与前三页同一条规矩：值必须来自真库；原生 my_modules **没有** purpose / plan /
# 业务编号 / 显式负责人这些承载面，一律走 addon 自有表 eln_ui_task_profiles，
# 取不到就显式留白（'—'），不许拿原型演示文案顶。
#
# 这里额外钉两件前面几页没钉过的事：
#   1. 原生表一字不动（32 列的 my_modules 不因为二开多一列）；
#   2. 模型必须裹在 Scinote::ElnUi 里（2026-10-04 写成顶层 class 直接让容器 boot 失败）。

require_relative 'test_helper'

class ElnUiTaskDetailTest < AcTest::Base
  include Warden::Test::Helpers

  def test_task_profile_carries_native_missing_fields
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    task = make_task!(experiment: exp, creator: scene[:creator])

    Scinote::ElnUi::TaskProfile.upsert_for!(task,
                                            business_code: 'ELN-TASK-2026-067',
                                            purpose: '摸清发泡剂用量对泡孔结构的影响窗口',
                                            plan: '称料 → 混炼 → 程序升温发泡 → 取样',
                                            owner_user: scene[:creator],
                                            source: 'seed')

    profile = Scinote::ElnUi::TaskProfile.find_by(my_module_id: task.id)
    assert_equal 'ELN-TASK-2026-067', profile.business_code
    assert_equal '摸清发泡剂用量对泡孔结构的影响窗口', profile.purpose
    assert_equal scene[:creator].id, profile.owner_user_id

    payload = Scinote::ElnUi::MyModuleDetailPayload.call(task, scene[:creator])
    # ⚠ 键名是 taskName（不是 name）：payload 的键跟着原型 TaskDetail.vue 的字段走，
    #   别照前三页的 :name 想当然。
    assert_equal task.name, payload[:taskName], '任务名来自原生 my_modules.name'
    assert_includes payload.to_json, 'ELN-TASK-2026-067', '业务编号必须进 payload（页面才显示得出）'
  end

  # upsert 幂等：同一个任务反复写入只留一行，且后写覆盖前写（seed 可以放心重跑）
  def test_upsert_is_idempotent
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    task = make_task!(experiment: exp, creator: scene[:creator])

    2.times do |i|
      Scinote::ElnUi::TaskProfile.upsert_for!(task, purpose: "第 #{i} 版目的")
    end

    assert_equal 1, Scinote::ElnUi::TaskProfile.where(my_module_id: task.id).count, 'upsert 不能留下两行'
    assert_equal '第 1 版目的', Scinote::ElnUi::TaskProfile.find_by(my_module_id: task.id).purpose
  end

  # 没有二开档案时是**留白**而不是崩、也不是回落原型演示文案
  def test_missing_profile_renders_dash_not_demo_text
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    task = make_task!(experiment: exp, creator: scene[:creator])

    payload = Scinote::ElnUi::MyModuleDetailPayload.call(task, scene[:creator])

    refute_includes payload.to_json, 'ADH-6066', '绝不回落原型演示文案'
    assert_nil Scinote::ElnUi::TaskProfile.find_by(my_module_id: task.id), '本用例前提：没有二开档案'
  end

  # 🔴 原生表一字不动：my_modules 的列数不因为二开变多
  def test_native_my_modules_schema_untouched
    cols = MyModule.column_names
    %w[purpose plan business_code owner_user_id].each do |c|
      refute_includes cols, c, "原生 my_modules 不能出现二开列 #{c}"
    end
  end

  # 视图契约：挂载点 / 数据块 / bundle 三件套（与前三页同一套命名规矩）
  # ============================================================
  # 下钻URL（2026-10-05）
  # ============================================================

  # 面包屑三段都要能点回上一层 —— URL 由 payload 下发，前端不许自己拼宿主路由。
  def test_crumb_carries_project_and_experiment_urls
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    task = make_task!(experiment: exp, creator: scene[:creator])

    crumb = Scinote::ElnUi::MyModuleDetailPayload.call(task, scene[:creator])[:crumb]
    assert_equal '/eln_project_list', crumb[:listUrl], '第一级回addon 列表页'
    assert_equal "/projects/#{scene[:project].id}/eln_project_detail", crumb[:projectUrl]
    assert_equal "/experiments/#{exp.id}/eln_exp_detail", crumb[:experimentUrl]
  end

  # 没 project 的实验（原生允许）→ projectUrl 必须是 nil，不能编一个 /projects//eln_...
  def test_crumb_project_url_is_nil_without_project
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    task = make_task!(experiment: exp, creator: scene[:creator])

    crumb = Scinote::ElnUi::MyModuleDetailPayload.call(task, scene[:creator])[:crumb]
    # 有 project 时必须是合法路径（这个断言同时锁住「不许出现空段拼接」）
    assert_equal false, crumb[:projectUrl].to_s.include?('//eln_'), '不得拼出 /projects//eln_… 这种坏地址'
  end

  def test_task_detail_page_mounts_vue_bundle
    scene = build_scene!
    exp = make_experiment!(project: scene[:project], creator: scene[:creator])
    task = make_task!(experiment: exp, creator: scene[:creator])

    session = ActionDispatch::Integration::Session.new(Rails.application)
    Warden.on_next_request { |proxy| proxy.set_user(scene[:creator], scope: :user) }
    session.get("/experiments/#{exp.id}/my_modules/#{task.id}/eln_task_detail")
    html = session.response.body

    assert_equal 200, session.response.status, '任务创建者应能打开任务详情页'
    assert_includes html, 'id="eln-task-detail"', '挂载点必须存在'
    assert_includes html, 'id="eln-task-detail-data"', '数据注入块必须存在'
    # ⚠ 断言不带扩展名：precompile 之后 HTML 里是 digest 文件名
    assert_includes html, 'eln_task_detail', 'Vue bundle 必须被引入'
    assert_includes html, task.name, '页面必须带真任务名'
  end
end
