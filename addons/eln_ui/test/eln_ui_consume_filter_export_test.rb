# frozen_string_literal: true

# ELN UI —— 消耗/执行明细筛选 + 导出（报告 §5 第 6 项 #12 · spec REQ-RES-CONSUME 末段）
#
# 验证：ResCenterPayload 在给定 filters 时只返回匹配行；ConsumeCsvExport 输出合法 CSV；
# 筛选只影响 consume 侧，不污染 cost_block 的全量口径。
require_relative 'test_helper'

class ElnUiConsumeFilterExportTest < AcTest::Base
  include ElnUiFactories

  def setup
    @scene   = build_scene!
    @team    = @scene[:team]
    @project = @scene[:project]
    @user_a  = @scene[:creator]
    @user_b  = make_user!(name: '操作人B')
    join_team!(@user_b, @team)
    @proj2   = make_project!(team: @team, creator: @user_a)
  end

  def payload(filters = {})
    Scinote::ElnUi::ResCenterPayload.call(user: @user_a, team: @team, filters: filters)
  end

  def test_filter_by_type_material
    make_consume_record!(project: @project, user: @user_a, kind: 'material', name: '试剂A', source_id: 11_001)
    make_consume_record!(project: @project, user: @user_a, kind: 'service', name: 'DSC', source_id: 11_002)
    rows = payload(type: 'material')[:consume][:rows]
    assert_operator rows.size, :>=, 1
    assert(rows.all? { |r| r[:type] == '物资' }, '按类型=物资筛选后只剩物资行')
  end

  def test_filter_by_type_service
    make_consume_record!(project: @project, user: @user_a, kind: 'material', name: '试剂A', source_id: 12_001)
    make_consume_record!(project: @project, user: @user_a, kind: 'service', name: 'DSC', source_id: 12_002)
    rows = payload(type: 'service')[:consume][:rows]
    assert(rows.all? { |r| r[:type] == '服务' }, '按类型=服务筛选后只剩服务行')
  end

  def test_filter_by_project
    make_consume_record!(project: @project, user: @user_a, name: '在P1', source_id: 13_001)
    make_consume_record!(project: @proj2,   user: @user_a, name: '在P2', source_id: 13_002)
    rows = payload(project_id: @proj2.id)[:consume][:rows]
    assert_operator rows.size, :>=, 1
    assert(rows.all? { |r| r[:project] == @proj2.name }, '按项目筛选后只剩该项目行')
  end

  def test_filter_by_user
    make_consume_record!(project: @project, user: @user_a, name: 'A做的', source_id: 14_001)
    make_consume_record!(project: @project, user: @user_b, name: 'B做的', source_id: 14_002)
    rows = payload(user_id: @user_b.id)[:consume][:rows]
    assert(rows.all? { |r| r[:user].include?(@user_b.full_name) }, '按用户筛选后只剩该用户行')
  end

  def test_filter_by_date_range
    make_consume_record!(project: @project, user: @user_a, name: '早期', occurred_at: Date.new(2026, 1, 5), source_id: 15_001)
    make_consume_record!(project: @project, user: @user_a, name: '近期', occurred_at: Date.new(2026, 9, 20), source_id: 15_002)
    rows = payload(range_from: '2026-06-01', range_to: '2026-12-31')[:consume][:rows]
    assert(rows.any? { |r| r[:name] == '近期' }, '时间范围内应包含近期行')
    refute(rows.any? { |r| r[:name] == '早期' }, '时间范围外应排除早期行')
  end

  def test_empty_filter_returns_all
    make_consume_record!(project: @project, user: @user_a, name: 'x', source_id: 16_001)
    assert_operator payload[:consume][:rows].size, :>=, 1
    empty = payload(type: '', project_id: '', user_id: '', range_from: '', range_to: '')[:consume][:rows]
    assert_operator empty.size, :>=, 1, '全空筛选条件等同于不过滤'
  end

  def test_consume_block_exposes_filter_options_with_ids
    rec_p1 = make_consume_record!(project: @project, user: @user_a, name: 'p1行', source_id: 19_001)
    make_consume_record!(project: @proj2,   user: @user_b, name: 'p2行', source_id: 19_002)
    consume = payload[:consume]
    projects = consume[:projects]
    users = consume[:users]
    assert_operator projects.size, :>=, 2, '筛选下拉应包含出现过的全部项目'
    assert_operator users.size, :>=, 2, '筛选下拉应包含出现过的全部操作人'
    assert(projects.any? { |p| p[:id] == @project.id }, '项目选项带真实 id 供导出回传')
    assert(users.any? { |u| u[:id] == @user_b.id }, '用户选项带真实 id 供导出回传')
  end

  def test_cost_block_unaffected_by_filter
    make_consume_record!(project: @project, user: @user_a, kind: 'material', amount: 100, source_id: 17_001)
    unfiltered = payload[:cost][:stats]
    filtered   = payload(type: 'service')[:cost][:stats] # 筛成空，花费口径仍全量
    assert_equal unfiltered, filtered, 'cost_block 不受 consume 筛选影响（始终全量口径）'
  end

  def test_csv_export_contains_headers_and_rows
    make_consume_record!(project: @project, user: @user_a, kind: 'material', name: '试剂A',
                         quantity: 2, unit: '瓶', unit_price: 50, amount: 100, source_id: 18_001)
    recs = Scinote::ElnUi::ResCenterPayload.filtered_consume_records(user: @user_a, team: @team)
    csv = Scinote::ElnUi::ConsumeCsvExport.generate(recs)
    assert_includes csv, '时间,类型,名称,数量,单价,金额,项目,操作人,状态'
    assert_includes csv, '试剂A'
    assert_includes csv, '¥100'
  end
end
