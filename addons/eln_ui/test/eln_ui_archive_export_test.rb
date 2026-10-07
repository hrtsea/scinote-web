# frozen_string_literal: true

# ELN UI —— 归档导出（报告 §5 第 6 项 #10 · spec SCN-PM-ARCH-1/2/3）
#
# 验证：ProjectDetailPayload 下发 projectArchive（真实归档态 + 导出入口）；
# ProjectArchiveExport 把项目结构化数据渲染成 CSV 预览包。
require_relative 'test_helper'

class ElnUiArchiveExportTest < AcTest::Base
  include ElnUiFactories

  def setup
    @scene   = build_scene!
    @team    = @scene[:team]
    @project = @scene[:project]
    @creator = @scene[:creator]
  end

  def test_payload_contains_archive_block
    detail = Scinote::ElnUi::ProjectDetailPayload.call(@project)
    archive = detail[:projectArchive]
    assert_equal false, archive[:archived]
    assert archive[:canExport]
    assert archive[:exportUrl].include?(@project.id.to_s)
  end

  def test_export_csv_includes_project_name
    exp = make_experiment!(project: @project, creator: @creator)
    make_task!(experiment: exp, creator: @creator)
    csv = Scinote::ElnUi::ProjectArchiveExport.call(@project)
    assert_includes csv, @project.name
    assert_includes csv, '区块,字段,值'
    assert_includes csv, '项目基础'
    assert_includes csv, '实验'
  end
end
