# frozen_string_literal: true

# ELN UI —— 指标状态由任务审核关闭驱动（报告 §5 第 6 项 #11 · spec REQ-PM-INDICATOR / SCN-PM-IND-3/4/5）
#
# 验证：ProjectDetailPayload 下发 taskCloseReview，聚合本项目全部任务的关闭审核态；
# 全部关闭 → indicatorDriven=true（指标达标由任务关闭驱动）。
require_relative 'test_helper'

class ElnUiIndicatorLinkageTest < AcTest::Base
  include ElnUiFactories

  def setup
    @scene    = build_scene!
    @team     = @scene[:team]
    @project  = @scene[:project]
    @creator  = @scene[:creator]
    @member   = add_member!(@project, @team, assigner: @creator, role: :normal, name: '组员')
  end

  def payload
    Scinote::ElnUi::ProjectDetailPayload.call(@project)
  end

  def test_review_reflects_close_state
    exp  = make_experiment!(project: @project, creator: @creator)
    task = make_task!(experiment: exp, creator: @creator)
    make_task_close_request!(my_module: task, submitted_by: @member, status: 'approved')
    review = payload[:taskCloseReview]
    assert_equal 1, review[:total]
    assert_equal 1, review[:closed]
    assert review[:indicatorDriven], '全部任务关闭 → 指标达标可驱动'
    assert_equal 'approved', review[:tasks].first[:state]
    assert review[:tasks].first[:detailUrl].include?('/eln_task_detail')
  end

  def test_no_close_requests_yields_none_state
    exp = make_experiment!(project: @project, creator: @creator)
    make_task!(experiment: exp, creator: @creator)
    review = payload[:taskCloseReview]
    assert_equal 1, review[:total]
    assert_equal 0, review[:closed]
    refute review[:indicatorDriven]
    assert_equal 'none', review[:tasks].first[:state]
    assert_equal '未提交关闭申请', review[:tasks].first[:stateLabel]
  end

  def test_partial_close_not_driven
    exp = make_experiment!(project: @project, creator: @creator)
    t1  = make_task!(experiment: exp, creator: @creator)
    t2  = make_task!(experiment: exp, creator: @creator)
    make_task_close_request!(my_module: t1, submitted_by: @member, status: 'approved')
    make_task_close_request!(my_module: t2, submitted_by: @member, status: 'pending')
    review = payload[:taskCloseReview]
    assert_equal 2, review[:total]
    assert_equal 1, review[:closed]
    assert_equal 1, review[:pending]
    refute review[:indicatorDriven], '仅部分任务关闭 → 指标达标未驱动'
  end
end
