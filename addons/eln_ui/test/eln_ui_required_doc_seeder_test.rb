# frozen_string_literal: true

# ELN UI —— 必传文档固定清单补种器（ADR-0049 / spec §4.2）
#
# 守 6 件事：无 profile 不种、空台账建 5 行规范序、幂等、保留已上传行、
# position 归一、非规范名旧行不碰。
#
# 对拍铁律：把 seed! 里的 position 归一一行摘掉 ⇒ position 用例必须精确变红
# （证明护栏不是空转）。

require_relative 'test_helper'

class ElnUiRequiredDocSeederTest < AcTest::Base
  include ElnUiFactories

  NAMES = Scinote::ElnUi::RequiredDocSeeder::REQUIRED_DOC_NAMES

  # ------------------------------------------------------------
  # 闸门：未纳管项目不补种（D6）
  # ------------------------------------------------------------

  def test_unmanaged_project_is_not_seeded
    scene = build_scene!

    assert_equal 0, Scinote::ElnUi::RequiredDocSeeder.seed!(scene[:project])
    assert_equal 0, Scinote::ElnUi::ProjectDocument.where(project_id: scene[:project].id).count,
                 '无 profile 的项目一行都不建'
  end

  # ------------------------------------------------------------
  # 正常路径：空台账 → 5 行规范序，全部待上传
  # ------------------------------------------------------------

  def test_managed_project_without_docs_gets_five_canonical_rows
    scene = build_scene!
    Scinote::ElnUi::ProjectProfile.upsert_for!(scene[:project], {})

    assert_equal 5, Scinote::ElnUi::RequiredDocSeeder.seed!(scene[:project])

    docs = Scinote::ElnUi::ProjectDocument.where(project_id: scene[:project].id).required.to_a
    assert_equal NAMES, docs.map(&:name), '5 类规范序（与前端文档面板枚举一致）'
    assert_equal (1..5).to_a, docs.map(&:position), 'position 按规范序 1..5'
    assert docs.none?(&:uploaded), '新建行全部待上传（D2：空行=待上传槽位）'
  end

  # ------------------------------------------------------------
  # 幂等：第二次只归一不建行
  # ------------------------------------------------------------

  def test_seed_is_idempotent
    scene = build_scene!
    Scinote::ElnUi::ProjectProfile.upsert_for!(scene[:project], {})
    Scinote::ElnUi::RequiredDocSeeder.seed!(scene[:project])

    assert_equal 0, Scinote::ElnUi::RequiredDocSeeder.seed!(scene[:project])
    assert_equal 5, Scinote::ElnUi::ProjectDocument.where(project_id: scene[:project].id).count
  end

  # ------------------------------------------------------------
  # 既有已上传行：数据不重置，position 归位
  # ------------------------------------------------------------

  def test_existing_uploaded_row_is_preserved
    scene = build_scene!
    Scinote::ElnUi::ProjectProfile.upsert_for!(scene[:project], {})
    Scinote::ElnUi::ProjectDocument.create!(
      project_id: scene[:project].id, category: 'required', name: '项目任务书',
      version: 'v2', uploaded: true, uploaded_on: Date.new(2026, 3, 2), position: 0
    )

    assert_equal 4, Scinote::ElnUi::RequiredDocSeeder.seed!(scene[:project])

    task_book = Scinote::ElnUi::ProjectDocument.find_by(project_id: scene[:project].id, name: '项目任务书')
    assert task_book.uploaded, '已上传行不被重置'
    assert_equal 'v2', task_book.version
    assert_equal Date.new(2026, 3, 2), task_book.uploaded_on
    assert_equal 2, task_book.position, '既有行 position 归一到规范位'
  end

  # ------------------------------------------------------------
  # 非规范名旧行（如历史 _seed_ 前缀）：不碰（洗前缀是迁移的一次性职责，D5）
  # ------------------------------------------------------------

  def test_legacy_non_canonical_row_is_left_alone
    scene = build_scene!
    Scinote::ElnUi::ProjectProfile.upsert_for!(scene[:project], {})
    legacy = Scinote::ElnUi::ProjectDocument.create!(
      project_id: scene[:project].id, category: 'required',
      name: '_seed_立项申请材料', position: 9
    )

    assert_equal 5, Scinote::ElnUi::RequiredDocSeeder.seed!(scene[:project])

    legacy.reload
    assert_equal '_seed_立项申请材料', legacy.name, '补种器不改名（迁移才洗前缀）'
    assert_equal 9, legacy.position, '非规范名旧行 position 不归一'
    assert_equal 6, Scinote::ElnUi::ProjectDocument.where(project_id: scene[:project].id).count,
                 '5 规范行 + 1 遗留行'
  end
end
