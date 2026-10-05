# frozen_string_literal: true

require 'rails_helper'
require 'scinote/wechat_gateway'

module Scinote
  module WechatGateway
    RSpec.describe ScinoteServiceWriter do
      let(:user) { instance_double(User, id: 7) }
      let(:team) { double('team') }
      let(:project) { instance_double(Project, team: team) }
      let(:writer) { described_class.new(user) }

      before do
        allow(Scinote::WechatGateway.configuration).to receive(:default_project_id).and_return(99)
        allow(Project).to receive(:find).with(99).and_return(project)
        allow(writer).to receive(:can_create_project_experiments?).and_return(true)
      end

      describe '#create_experiment' do
        it '经 CreateExperimentService 创建并返回整数 id' do
          fake_exp = double('exp', id: 123)
          fake_svc = double('svc')
          expect(CreateExperimentService).to receive(:new)
            .with(user, team, hash_including(project: project, name: '标题', description: '正文'))
            .and_return(fake_svc)
          expect(fake_svc).to receive(:call).and_return(fake_exp)
          expect(writer.create_experiment('标题', '正文')).to eq(123)
        end

        it '可显式指定目标项目（微信端选项目后建实验）' do
          target = instance_double(Project, team: team)
          allow(Project).to receive(:find).with(55).and_return(target)
          allow(writer).to receive(:can_create_project_experiments?).with(user, target).and_return(true)
          fake_svc = double('svc')
          expect(CreateExperimentService).to receive(:new)
            .with(user, team, hash_including(project: target)).and_return(fake_svc)
          expect(fake_svc).to receive(:call).and_return(double('exp', id: 9))
          expect(writer.create_experiment('T', 'B', project_id: 55)).to eq(9)
        end

        it '无创建实验权限时抛中文错误（不触发 nil.id）' do
          allow(writer).to receive(:can_create_project_experiments?).with(user, project).and_return(false)
          expect(CreateExperimentService).not_to receive(:new)
          expect { writer.create_experiment('T', 'B') }.to raise_error(/无权限在该项目下创建实验/)
        end

        it '服务返回 nil 时抛错而非 NoMethodError' do
          fake_svc = double('svc')
          allow(CreateExperimentService).to receive(:new).and_return(fake_svc)
          allow(fake_svc).to receive(:call).and_return(nil)
          expect { writer.create_experiment('T', 'B') }.to raise_error(/创建实验失败/)
        end
      end

      describe '#project_available?' do
        it '不存在返回 false' do
          allow(Project).to receive(:find_by).with(id: 5).and_return(nil)
          expect(writer.project_available?(5)).to be false
        end

        it '已归档返回 false' do
          allow(Project).to receive(:find_by).with(id: 5).and_return(project)
          allow(project).to receive(:archived?).and_return(true)
          expect(writer.project_available?(5)).to be false
        end

        it '无 EXPERIMENTS_CREATE 权限返回 false' do
          allow(Project).to receive(:find_by).with(id: 5).and_return(project)
          allow(project).to receive(:archived?).and_return(false)
          allow(writer).to receive(:can_create_project_experiments?).with(user, project).and_return(false)
          expect(writer.project_available?(5)).to be false
        end

        it '未归档且有权限返回 true' do
          allow(Project).to receive(:find_by).with(id: 5).and_return(project)
          allow(project).to receive(:archived?).and_return(false)
          allow(writer).to receive(:can_create_project_experiments?).with(user, project).and_return(true)
          expect(writer.project_available?(5)).to be true
        end
      end

      describe '#append_task_note' do
        let(:mm) { instance_double(MyModule, id: 33, description: '旧内容') }

        it '追加到任务正文并写 last_modified_by，不覆盖原内容' do
          allow(MyModule).to receive(:find).with(33).and_return(mm)
          allow(writer).to receive(:can_update_my_module_description?).with(user, mm).and_return(true)
          expect(mm).to receive(:update!)
            .with(description: "旧内容\n新内容", last_modified_by: user).and_return(true)
          expect(writer.append_task_note(33, '新内容')).to be true
        end

        it '无「编辑描述」权限时抛中文错误' do
          allow(MyModule).to receive(:find).with(33).and_return(mm)
          allow(writer).to receive(:can_update_my_module_description?).with(user, mm).and_return(false)
          expect { writer.append_task_note(33, 'x') }.to raise_error(/无权限写入该任务/)
        end
      end

      describe '#my_module_available?' do
        let(:mm) { instance_double(MyModule, id: 33, archived?: false, team: team) }

        before { allow(MyModule).to receive(:find_by).with(id: 33).and_return(mm) }

        it '不存在返回 false' do
          allow(MyModule).to receive(:find_by).with(id: 33).and_return(nil)
          expect(writer.my_module_available?(33)).to be false
        end

        it '已归档返回 false' do
          allow(mm).to receive(:archived?).and_return(true)
          expect(writer.my_module_available?(33)).to be false
        end

        it '不可读返回 false（可见性是写的前提）' do
          rel = double('rel')
          allow(MyModule).to receive(:readable_by_user).with(user, team).and_return(rel)
          allow(rel).to receive(:exists?).with(id: 33).and_return(false)
          expect(writer.my_module_available?(33)).to be false
        end

        it '可读但无写权限返回 false（可读 ≠ 可写）' do
          rel = double('rel')
          allow(MyModule).to receive(:readable_by_user).with(user, team).and_return(rel)
          allow(rel).to receive(:exists?).with(id: 33).and_return(true)
          allow(writer).to receive(:can_update_my_module_description?).with(user, mm).and_return(false)
          expect(writer.my_module_available?(33)).to be false
        end

        it '可读且可写返回 true' do
          rel = double('rel')
          allow(MyModule).to receive(:readable_by_user).with(user, team).and_return(rel)
          allow(rel).to receive(:exists?).with(id: 33).and_return(true)
          allow(writer).to receive(:can_update_my_module_description?).with(user, mm).and_return(true)
          expect(writer.my_module_available?(33)).to be true
        end
      end

      describe '#get_project' do
        it '返回项目元信息' do
          p = instance_double(Project, id: 5, name: 'P', created_at: Time.new(2026, 9, 23))
          allow(Project).to receive(:find).with(5).and_return(p)
          expect(writer.get_project(5)).to eq(id: 5, title: 'P', date: '2026-09-23')
        end
      end

      describe '#list_projects' do
        it '跨团队收集 id，creatable 时施加 EXPERIMENTS_CREATE 过滤' do
          team_a = double('team_a', id: 1)
          team_b = double('team_b', id: 2)
          allow(user).to receive(:teams).and_return([team_a, team_b])

          per_team = double('per_team')
          allow(Project).to receive(:where).with(team_id: 1).and_return(per_team)
          allow(Project).to receive(:where).with(team_id: 2).and_return(per_team)
          allow(per_team).to receive(:readable_by_user).and_return(per_team)
          allow(per_team).to receive(:where).with(archived: false).and_return(per_team)
          expect(per_team).to receive(:with_granted_permissions)
            .with(user, ProjectPermissions::EXPERIMENTS_CREATE).twice.and_return(per_team)
          allow(per_team).to receive(:pluck).with(:id).and_return([11])

          final = double('final')
          allow(Project).to receive(:where).with(id: [11]).and_return(final)
          allow(final).to receive(:order).with(created_at: :desc).and_return(final)
          allow(final).to receive(:limit).with(5)
            .and_return([instance_double(Project, id: 11, name: 'P', created_at: nil)])

          expect(writer.list_projects).to eq([{ id: 11, title: 'P', date: '' }])
        end

        it 'scope: :readable 时不施加创建权限过滤' do
          team_a = double('team_a', id: 1)
          allow(user).to receive(:teams).and_return([team_a])
          per_team = double('per_team')
          allow(Project).to receive(:where).with(team_id: 1).and_return(per_team)
          allow(per_team).to receive(:readable_by_user).and_return(per_team)
          allow(per_team).to receive(:where).with(archived: false).and_return(per_team)
          expect(per_team).not_to receive(:with_granted_permissions)
          allow(per_team).to receive(:pluck).with(:id).and_return([11, 12])
          final = double('final')
          allow(Project).to receive(:where).with(id: [11, 12]).and_return(final)
          allow(final).to receive(:order).with(created_at: :desc).and_return(final)
          allow(final).to receive(:limit).with(5).and_return([])

          expect(writer.list_projects(scope: :readable)).to eq([])
        end
      end

      describe '#append_note' do
        it '拼接原正文并更新 description 与 last_modified_by' do
          exp = instance_double(Experiment, description: "旧正文")
          allow(Experiment).to receive(:find).with(5).and_return(exp)
          expect(exp).to receive(:update!)
            .with(description: "旧正文\n新块", last_modified_by: user)
          writer.append_note(5, '新块')
        end
      end

      describe '#get_experiment' do
        it '返回 id/title/date/project_id 元信息' do
          exp = instance_double(Experiment, id: 5, name: 'T', created_at: Time.new(2026, 9, 23), project_id: 3)
          allow(Experiment).to receive(:find).with(5).and_return(exp)
          expect(writer.get_experiment(5)).to eq(id: 5, title: 'T', date: '2026-09-23', project_id: 3)
        end
      end

      describe '#timestamp' do
        it '追加「🔒 完成于」行' do
          exp = instance_double(Experiment, description: '')
          allow(Experiment).to receive(:find).with(5).and_return(exp)
          expect(exp).to receive(:update!)
            .with(description: /🔒 完成于/, last_modified_by: user)
          writer.timestamp(5)
        end
      end

      describe '#list_experiments' do
        it '复用 Experiment.search 并映射结果' do
          rel = double('rel')
          allow(Experiment).to receive(:search).with(user, false, nil).and_return(rel)
          allow(rel).to receive(:limit).with(5)
            .and_return([instance_double(Experiment, id: 1, name: 'A', created_at: nil)])
          expect(writer.list_experiments(limit: 5)).to eq([{ id: 1, title: 'A', date: '' }])
        end
      end

      describe '#upload (v1 占位)' do
        it '以正文占位记录附件，不抛异常' do
          exp = instance_double(Experiment, description: '')
          allow(Experiment).to receive(:find).with(5).and_return(exp)
          expect(exp).to receive(:update!).with(description: /📎 附件：封面/, last_modified_by: user)
          writer.upload(5, 'https://cdn/p', '封面')
        end
      end

      describe '#assign_user (F6 指派)' do
        it '有 manage_users 权限时创建手动指派（normal 角色）' do
          exp = instance_double(Experiment, team: team)
          allow(Experiment).to receive(:find).with(5).and_return(exp)
          allow(writer).to receive(:can_manage_experiment_users?).with(user, exp).and_return(true)
          target = instance_double(User, id: 9)
          allow(User).to receive(:find).with(9).and_return(target)
          role = double('normal_role')
          allow(UserRole).to receive(:find_predefined_normal_user_role).and_return(role)

          ua = double('user_assignment')
          assoc = double('assoc')
          allow(exp).to receive(:user_assignments).and_return(assoc)
          allow(assoc).to receive(:find_or_initialize_by).with(user: target, team: team).and_return(ua)
          expect(ua).to receive(:user_role=).with(role)
          expect(ua).to receive(:assigned_by=).with(user)
          expect(ua).to receive(:assigned=).with(:manually)
          expect(ua).to receive(:save!)

          expect(writer.assign_user(5, 9)).to be true
        end

        it 'owner 角色走 find_predefined_owner_role' do
          exp = instance_double(Experiment, team: team)
          allow(Experiment).to receive(:find).with(5).and_return(exp)
          allow(writer).to receive(:can_manage_experiment_users?).with(user, exp).and_return(true)
          allow(User).to receive(:find).with(9).and_return(instance_double(User, id: 9))
          role = double('owner_role')
          expect(UserRole).to receive(:find_predefined_owner_role).and_return(role)
          ua = double('ua')
          allow(exp).to receive(:user_assignments).and_return(double(find_or_initialize_by: ua))
          expect(ua).to receive(:user_role=).with(role)
          allow(ua).to receive(:assigned_by=)
          allow(ua).to receive(:assigned=)
          allow(ua).to receive(:save!)

          writer.assign_user(5, 9, role: :owner)
        end

        it '无权限时抛错且不写库' do
          exp = instance_double(Experiment, team: team)
          allow(Experiment).to receive(:find).with(5).and_return(exp)
          allow(writer).to receive(:can_manage_experiment_users?).with(user, exp).and_return(false)
          expect(exp).not_to receive(:user_assignments)
          expect { writer.assign_user(5, 9) }.to raise_error(/无权限指派/)
        end
      end

      describe '#admin_experiments (F9)' do
        it '非实例管理员抛错' do
          allow(InstanceAdmin).to receive(:admin?).with(user).and_return(false)
          expect { writer.admin_experiments }.to raise_error(/需要实例管理员权限/)
        end

        it '管理员跨用户查询实验' do
          allow(InstanceAdmin).to receive(:admin?).with(user).and_return(true)
          teams_rel = double('teams_rel')
          allow(user).to receive(:teams).and_return(teams_rel)
          allow(teams_rel).to receive(:pluck).with(:id).and_return([1])

          exp = instance_double(Experiment, id: 3, name: 'X', created_at: nil)
          scope = double('scope')
          allow(Experiment).to receive(:joins).with(:project).and_return(scope)
          allow(scope).to receive(:where).with(projects: { team_id: [1], archived: false }).and_return(scope)
          allow(scope).to receive(:order).with(created_at: :desc).and_return(scope)
          allow(scope).to receive(:limit).with(10).and_return([exp])

          expect(writer.admin_experiments).to eq([{ id: 3, title: 'X', date: '' }])
        end
      end

      describe '#book_equipment (F10)' do
        let(:repo) { double('repo') }

        it '权限通过时创建 CalendarEvent 预约' do
          row = instance_double(RepositoryRow, team: team, repository: repo)
          allow(RepositoryRow).to receive(:find).with(12).and_return(row)
          allow(Repository).to receive(:equipment_booking_enabled?).and_return(true)
          allow(writer).to receive(:can_create_equipment_bookings?).with(user, repo).and_return(true)

          event = double('event', id: 77, name: '设备预约')
          expect(CalendarEvent).to receive(:create!).with(
            hash_including(subject: row, team: team, created_by: user,
                           event_type: :equipment_booking)
          ).and_return(event)

          start_t = Time.new(2026, 9, 24, 14, 0)
          end_t = Time.new(2026, 9, 24, 16, 0)
          expect(writer.book_equipment(12, start_time: start_t, end_time: end_t))
            .to eq(id: 77, name: '设备预约')
        end

        it '未开启预约功能抛错' do
          row = instance_double(RepositoryRow, team: team, repository: repo)
          allow(RepositoryRow).to receive(:find).with(12).and_return(row)
          allow(Repository).to receive(:equipment_booking_enabled?).and_return(false)
          expect do
            writer.book_equipment(12, start_time: Time.now, end_time: Time.now)
          end.to raise_error(/未开启设备预约/)
        end

        it '无预约权限抛错' do
          row = instance_double(RepositoryRow, team: team, repository: repo)
          allow(RepositoryRow).to receive(:find).with(12).and_return(row)
          allow(Repository).to receive(:equipment_booking_enabled?).and_return(true)
          allow(writer).to receive(:can_create_equipment_bookings?).with(user, repo).and_return(false)
          expect do
            writer.book_equipment(12, start_time: Time.now, end_time: Time.now)
          end.to raise_error(/无权限预约/)
        end
      end

      describe '未配置默认项目' do
        it 'create_experiment 抛清晰错误' do
          allow(Scinote::WechatGateway.configuration).to receive(:default_project_id).and_return(nil)
          expect { writer.create_experiment('x', 'y') }
            .to raise_error(/WECHAT_GATEWAY_PROJECT_ID 未配置/)
        end
      end
    end
  end
end
