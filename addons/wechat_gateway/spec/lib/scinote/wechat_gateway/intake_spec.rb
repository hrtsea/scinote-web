# frozen_string_literal: true

require 'rails_helper'
require 'scinote/wechat_gateway'

module Scinote
  module WechatGateway
    RSpec.describe Intake do
      let(:store) { SessionDraftStore.new }
      let(:backend) { FakeBackend.new }
      # 默认项目 42（FakeBackend 对任意正整数项目都视为可建实验）
      let(:state_store) { MemoryUserStateStore.new.tap { |s| s.set_default_project(1, 42) } }
      let(:intake) { described_class.new(backend: backend, store: store, state_store: state_store) }

      def msg(text: '', media: [])
        Message.new(user_id: 'u1', text: text, media: media, type: :text, platform: :wecom)
      end

      # 内存后端桩：忠实模拟 ScinoteServiceWriter 的接口与副作用
      class FakeBackend
        attr_reader :experiments, :notes, :uploads, :timestamps, :assignments,
                    :admin_queries, :bookings, :formulations, :completed,
                    :projects, :my_modules, :project_queries, :task_notes

        def initialize
          @seq = 0
          @experiments = {}
          @projects = {}
          @my_modules = {}
          @notes = {}
          @task_notes = {}
          @uploads = []
          @timestamps = []
          @assignments = []
          @admin_queries = []
          @bookings = []
          @formulations = []
          @project_queries = []
          @unavailable = []
          @unavailable_modules = []
        end

        # 测试辅助：把某项目标记为「不可建实验」（无权限/已归档）
        def deny_project(project_id)
          @unavailable << project_id.to_i
        end

        def project_available?(project_id)
          project_id.to_i.positive? && !@unavailable.include?(project_id.to_i)
        end

        def get_project(project_id)
          p = @projects[project_id.to_i]
          { id: project_id.to_i, title: p ? p[:name] : "项目#{project_id}", date: '2026-09-23' }
        end

        # ---- Task（MyModule）级 ----

        # 测试辅助：把某任务标记为「不可写/不可读」（无权限或已归档）
        def deny_mymodule(mm_id)
          @unavailable_modules << mm_id.to_i
        end

        def my_module_available?(mm_id)
          mm_id.to_i.positive? && !@unavailable_modules.include?(mm_id.to_i)
        end

        def get_my_module(mm_id)
          m = @my_modules[mm_id.to_i]
          raise "任务 ##{mm_id} 不存在" unless m

          { id: mm_id.to_i, title: m[:name], date: '2026-09-23',
            experiment_id: m[:experiment_id],
            project_id: (@experiments[m[:experiment_id]] || {})[:project_id] }
        end

        def append_task_note(mm_id, block)
          (@task_notes[mm_id.to_i] ||= []) << block
          true
        end

        def upload_task(mm_id, path, caption)
          @uploads << { task_id: mm_id.to_i, path: path, caption: caption }
          true
        end

        def persist_formulation(record, exp_id)
          @formulations << { record: record, exp_id: exp_id }
          true
        end

        def assign_user(exp_id, target_user_id, role: :normal)
          @assignments << { exp_id: exp_id, user_id: target_user_id, role: role }
          true
        end

        def admin_experiments(query: nil, team_id: nil, limit: 10)
          @admin_queries << { query: query, team_id: team_id, limit: limit }
          @experiments.map { |id, e| { id: id, title: e[:title], date: '2026-09-23' } }
        end

        def book_equipment(row_id, start_time:, end_time:, name: nil)
          @bookings << { row_id: row_id, start_time: start_time, end_time: end_time, name: name }
          { id: 77, name: '设备预约' }
        end

        def create_experiment(title, body, start_date: nil, due_date: nil, project_id: nil)
          @seq += 1
          @experiments[@seq] = { title: title, body: body, start_date: start_date,
                                 due_date: due_date, project_id: project_id }
          @notes[@seq] = [body]
          @seq
        end

        def create_project(name, description = nil, start_date: nil, due_date: nil, read_only: false)
          @seq += 1
          @projects[@seq] = { name: name, description: description,
                              start_date: start_date, due_date: due_date, read_only: read_only }
          @seq
        end

        def create_mymodule(experiment_id, name, description = nil, due_date: nil)
          @seq += 1
          @my_modules[@seq] = { experiment_id: experiment_id, name: name, due_date: due_date }
          @seq
        end

        def list_projects(limit: 5, scope: :creatable)
          @project_queries << { limit: limit, scope: scope }
          rows = @projects.reject { |_, p| scope.to_sym == :creatable && p[:read_only] }
          rows.map { |id, p| { id: id, title: p[:name], date: '2026-09-23' } }.first(limit)
        end

        def list_mymodules(experiment_id, limit: 5)
          @my_modules.select { |_, m| m[:experiment_id] == experiment_id }
                     .map { |id, m| { id: id, title: m[:name], date: '2026-09-23' } }.first(limit)
        end

        def complete_experiment(exp_id)
          (@completed ||= []) << exp_id
          true
        end

        def append_note(exp_id, block)
          (@notes[exp_id] ||= []) << block
          true
        end

        def get_experiment(exp_id)
          raise 'not found' unless @experiments[exp_id]

          { id: exp_id, title: @experiments[exp_id][:title], date: '2026-09-23',
            project_id: @experiments[exp_id][:project_id] }
        end

        def upload(exp_id, path, caption)
          @uploads << { exp_id: exp_id, path: path, caption: caption }
          true
        end

        def list_experiments(q: nil, limit: 5)
          @experiments.map { |id, e| { id: id, title: e[:title], date: '2026-09-23' } }
        end

        def timestamp(exp_id)
          @timestamps << exp_id
          true
        end
      end

      describe '#handle' do
        it '/newexp 新建草稿并返回实验 id' do
          reply = intake.handle(1, msg(text: '/newexp'))
          expect(reply).to match(/🆕 已开新实验草稿 #1/)
          expect(backend.experiments[1][:title]).to eq('微信记录-1')
        end

        it '纯文本追加到当前草稿' do
          intake.handle(1, msg(text: '/newexp'))
          reply = intake.handle(1, msg(text: '今天做了萃取'))
          expect(reply).to match(/📝 已记录到 #1/)
          expect(backend.notes[1].last).to match(/\[.*· 文本\] 今天做了萃取/)
        end

        it '/setexp 设置当前实验' do
          eid = backend.create_experiment('已有', 'body')
          reply = intake.handle(1, msg(text: "/setexp #{eid}"))
          expect(reply).to match(/🎯 当前实验已设为 #/)
          expect(store.get(1)[:exp_id]).to eq(eid)
        end

        it '/getexp 查看当前实验' do
          eid = backend.create_experiment('已有', 'body')
          intake.handle(1, msg(text: "/setexp #{eid}"))
          expect(intake.handle(1, msg(text: '/getexp'))).to match(/🎯 当前实验：#/)
        end

        it '/getexp 无当前实验时给下一步指引' do
          expect(intake.handle(1, msg(text: '/getexp'))).to match(/当前未指定实验/)
        end

        it '已重命名的 /exp 不再被识别为指令' do
          backend.create_experiment('已有', 'body')
          reply = intake.handle(1, msg(text: '/exp'))
          expect(reply).not_to match(/🎯 当前实验：#/)
        end

        it '/setexp 缺/非法参数给用法提示' do
          expect(intake.handle(1, msg(text: '/setexp'))).to match(%r{用法：/setexp})
          expect(intake.handle(1, msg(text: '/setexp abc'))).to match(%r{用法：/setexp})
        end

        it '已删除的 /use 不再被识别为指令' do
          backend.create_experiment('已有', 'body')
          reply = intake.handle(1, msg(text: '/use 1'))
          expect(reply).not_to match(/🎯 当前实验已设为/)
          expect(state_store.pending(1)).to be_nil
        end

        it '#<id> 文本 消息级挂接' do
          eid = backend.create_experiment('T', 'body')
          intake.handle(1, msg(text: "/setexp #{eid}"))
          reply = intake.handle(1, msg(text: "#{eid} 补充备注"))
          expect(reply).to match(/🎯 当前实验已设为/)
          expect(backend.notes[eid].last).to match(/补充备注/)
        end

        it '/done 真实收尾并清草稿' do
          intake.handle(1, msg(text: '/newexp'))
          reply = intake.handle(1, msg(text: '/done'))
          expect(reply).to match(/🔒 实验 #1 已收尾/)
          expect(reply).to match(/已完成/)
          expect(backend.completed).to include(1)
          expect(store.get(1)).to be_nil
        end

        it '/cancel 清草稿但保留实验' do
          intake.handle(1, msg(text: '/newexp'))
          reply = intake.handle(1, msg(text: '/cancel'))
          expect(reply).to match(/🗑️ 草稿 #1 保留/)
          expect(store.get(1)).to be_nil
          expect(backend.experiments[1]).to be_present
        end

        it '/listexp 列出实验' do
          backend.create_experiment('A', 'body')
          reply = intake.handle(1, msg(text: '/listexp'))
          expect(reply).to match(/最近的实验/)
        end

        it '/listexp 支持数量参数' do
          backend.create_experiment('A', 'body')
          expect(intake.handle(1, msg(text: '/listexp 3'))).to match(/最近的实验/)
        end

        it '/search 关键词搜索' do
          backend.create_experiment('萃取实验', 'body')
          reply = intake.handle(1, msg(text: '/search 萃取'))
          expect(reply).to match(/搜索结果/)
        end

        it '媒体消息作为附件记录并自动建草稿' do
          media = [{ kind: :image, url: 'https://cdn/p', file_name: 'p.png' }]
          reply = intake.handle(1, msg(text: '', media: media))
          expect(reply).to match(/📎 图片已作为附件挂到实验 #1/)
          expect(backend.uploads).not_to be_empty
        end

        it '未知命令的纯文本自动建草稿并追加' do
          reply = intake.handle(1, msg(text: '随手记一条'))
          expect(reply).to match(/📝 已记录到 #1/)
        end

        it '不存在的 /setexp 目标返回友好提示' do
          reply = intake.handle(1, msg(text: '/setexp 999'))
          expect(reply).to match(/⚠️ 实验 #999 不存在或无权访问/)
        end

        it '/confirm 软锁定草稿并追加确认行' do
          intake.handle(1, msg(text: '/newexp'))
          reply = intake.handle(1, msg(text: '/confirm'))
          expect(reply).to match(/🔒 实验 #1 已软锁定/)
          expect(backend.notes[1].last).to match(/✅ 已确认/)
          expect(store.locked?(1)).to be true
        end

        it '锁定后追加文本被拒收' do
          intake.handle(1, msg(text: '/newexp'))
          intake.handle(1, msg(text: '/confirm'))
          reply = intake.handle(1, msg(text: '后续补充'))
          expect(reply).to match(/⚠️ 当前草稿已锁定/)
          expect(backend.notes[1].last).to match(/✅ 已确认/) # 未被新文本污染
        end

        it '锁定后 /newexp 可开新草稿解除锁定' do
          intake.handle(1, msg(text: '/newexp'))
          intake.handle(1, msg(text: '/confirm'))
          intake.handle(1, msg(text: '/newexp'))
          expect(store.locked?(1)).to be false
        end

        it '无草稿时 /confirm 提示无法锁定' do
          reply = intake.handle(1, msg(text: '/confirm'))
          expect(reply).to match(/当前没有进行中的草稿/)
        end

        it '/unlock 解除软锁后可继续追加' do
          intake.handle(1, msg(text: '/newexp'))
          intake.handle(1, msg(text: '/confirm'))
          expect(store.locked?(1)).to be true
          reply = intake.handle(1, msg(text: '/unlock'))
          expect(reply).to match(/🔓 实验 #1 已解除锁定/)
          expect(store.locked?(1)).to be false
          expect(intake.handle(1, msg(text: '继续补充'))).to match(/📝 已记录到 #1/)
        end

        it '未锁定时 /unlock 提示无需解锁' do
          intake.handle(1, msg(text: '/newexp'))
          reply = intake.handle(1, msg(text: '/unlock'))
          expect(reply).to match(/未锁定，无需解锁/)
        end

        it '/help 输出全部指令用法' do
          reply = intake.handle(1, msg(text: '/help'))
          expect(reply).to match(/微信录入指令一览/)
          expect(reply).to match(%r{/new})
          expect(reply).to match(%r{/unlock})
          expect(reply).to match(%r{/bind})
        end

        it '/help 带多余参数也返回帮助' do
          expect(intake.handle(1, msg(text: '/help 啥'))).to match(/微信录入指令一览/)
        end

        it '/newexp 可带标题与起止日期' do
          reply = intake.handle(1, msg(text: '/newexp PP配方A @2026-09-24 ~2026-10-01'))
          expect(reply).to match(/🆕 已开新实验草稿 #1「PP配方A」/)
          expect(reply).to match(/起始 2026-09-24/)
          expect(reply).to match(/截止 2026-10-01/)
          expect(backend.experiments[1][:title]).to eq('PP配方A')
          expect(backend.experiments[1][:start_date]).to eq(Date.new(2026, 9, 24))
          expect(backend.experiments[1][:due_date]).to eq(Date.new(2026, 10, 1))
        end

        it '/newexp 仅带日期时标题回退默认' do
          reply = intake.handle(1, msg(text: '/newexp @2026-09-24'))
          expect(reply).to match(/🆕 已开新实验草稿 #1/)
          expect(backend.experiments[1][:title]).to eq('微信记录-1')
          expect(backend.experiments[1][:start_date]).to eq(Date.new(2026, 9, 24))
          expect(backend.experiments[1][:due_date]).to be_nil
        end

        it '/newexp 非法日期被忽略且不报错' do
          reply = intake.handle(1, msg(text: '/newexp 实验 @notadate'))
          expect(reply).to match(/🆕 已开新实验草稿 #1/)
          expect(backend.experiments[1][:start_date]).to be_nil
        end

        it '/newexp 存在未收尾开放草稿时给出提醒' do
          intake.handle(1, msg(text: '/newexp'))
          reply = intake.handle(1, msg(text: '/newexp'))
          expect(reply).to match(/🆕 已开新实验草稿 #2/)
          expect(reply).to match(/未收尾的草稿 #1/)
        end

        it '/newexp 对已锁定的旧草稿不重复提醒' do
          intake.handle(1, msg(text: '/newexp'))
          intake.handle(1, msg(text: '/confirm'))
          reply = intake.handle(1, msg(text: '/newexp'))
          expect(reply).not_to match(/未收尾的草稿/)
        end

        context '群 @ 指派（F6）' do
          let(:resolver) { ->(wid, _plat) { wid == 'wx_u1' ? 9 : nil } }
          let(:intake) do
            described_class.new(backend: backend, store: store, mention_resolver: resolver)
          end

          it '已绑定的 @ 用户被指派到当前草稿' do
            intake.handle(1, msg(text: '/newexp'))
            m = msg(text: '做成像')
            m.mentions = ['wx_u1']
            reply = intake.handle(1, m)
            expect(reply).to match(/已指派 wx_u1（SciNote 用户 #9）到实验 #1/)
            expect(backend.assignments).to eq([{ exp_id: 1, user_id: 9, role: :normal }])
          end

          it '未绑定的 @ 返回提示且不指派' do
            intake.handle(1, msg(text: '/newexp'))
            m = msg(text: 'x')
            m.mentions = ['wx_unknown']
            reply = intake.handle(1, m)
            expect(reply).to match(/未绑定 SciNote，无法指派/)
            expect(backend.assignments).to be_empty
          end

          it '@ 指派会自动建立草稿' do
            m = msg(text: '立刻开工')
            m.mentions = ['wx_u1']
            reply = intake.handle(1, m)
            expect(reply).to match(/已指派 wx_u1/)
            expect(backend.assignments.first[:exp_id]).to eq(1)
          end
        end

        context '图片视觉识别（Ticket 05）' do
          it '识别成功则把文本写入正文' do
            intake_v = described_class.new(
              backend: backend, store: store, vision_describer: ->(_m) { '菌落呈圆形' }
            )
            media = [{ kind: :image, url: 'https://cdn/p', file_name: 'p.png' }]
            reply = intake_v.handle(1, msg(text: '', media: media))
            expect(reply).to match(/识别文本已写入正文/)
            expect(backend.notes[1].last).to match(/图片识别：菌落呈圆形/)
          end

          it '识别返回 nil 时降级为仅附件' do
            intake_f = described_class.new(
              backend: backend, store: store, vision_describer: ->(_m) { nil }
            )
            media = [{ kind: :image, url: 'https://cdn/p' }]
            reply = intake_f.handle(1, msg(text: '', media: media))
            expect(reply).to match(/📎 图片已作为附件/)
          end

          it '未配置识别时降级为仅附件' do
            media = [{ kind: :image, url: 'https://cdn/p' }]
            reply = intake.handle(1, msg(text: '', media: media))
            expect(reply).to match(/📎 图片已作为附件/)
          end
        end

        context 'AI 结构化抽取（Ticket 06）' do
          let(:record) do
            AiProcessor::StructuredRecord.new(
              experiment_title: 'T', components: [], results: [], process_params: {}, notes: ''
            )
          end

          it 'AI 可用时写入 GLP 正文并落 Formulation' do
            intake_ai = described_class.new(backend: backend, store: store, ai_llm: ->(_t) { record })
            intake_ai.handle(1, msg(text: '/newexp'))
            reply = intake_ai.handle(1, msg(text: '加了 100g PP'))
            expect(reply).to match(/已 AI 整理并写入 #1（草稿，需人工审核）/)
            expect(backend.notes[1].last).to include('【AI 辅助整理 · 需人工审核】')
            expect(backend.formulations.last[:exp_id]).to eq(1)
          end

          it 'AI 抽取失败降级为原文落库' do
            intake_bad = described_class.new(backend: backend, store: store, ai_llm: ->(_t) { raise 'boom' })
            intake_bad.handle(1, msg(text: '/newexp'))
            reply = intake_bad.handle(1, msg(text: '随手记'))
            expect(reply).to match(/📝 已记录到 #1/)
            expect(backend.formulations).to be_empty
          end

          it '未配置 AI 时走原文落库' do
            intake.handle(1, msg(text: '/newexp'))
            reply = intake.handle(1, msg(text: '随手记'))
            expect(reply).to match(/📝 已记录到 #1/)
            expect(backend.formulations).to be_empty
          end
        end

        context '管理员查询 F9' do
          it '/admin 列出查询结果' do
            backend.create_experiment('A', 'body')
            reply = intake.handle(1, msg(text: '/admin'))
            expect(reply).to match(/管理员查询（1）/)
          end

          it '/admin <关键词> 透传查询' do
            intake.handle(1, msg(text: '/admin 萃取'))
            expect(backend.admin_queries.last[:query]).to eq('萃取')
          end

          it '查询为空返回提示' do
            reply = intake.handle(1, msg(text: '/admin'))
            expect(reply).to match(/没有可展示的实验/)
          end
        end

        context '设备预约 F10' do
          it '/book 正常预约' do
            reply = intake.handle(1, msg(text: '/book 12 2026-09-24T14:00 2026-09-24T16:00'))
            expect(reply).to match(/已预约设备 12.*预约号 #77/)
            expect(backend.bookings.last[:row_id]).to eq(12)
            expect(backend.bookings.last[:start_time]).to be_a(Time)
          end

          it '/book 参数不足返回用法' do
            reply = intake.handle(1, msg(text: '/book 12'))
            expect(reply).to match(%r{用法：/book})
          end

          it '/book 非法时间报错' do
            reply = intake.handle(1, msg(text: '/book 12 notatime alsogarbage'))
            expect(reply).to match(/时间格式无效/)
            expect(backend.bookings).to be_empty
          end
        end

        context '扩展实体指令（/newexp /newproject /newtask /listproject /listexp /listtask）' do
          it '/newexp <标题> 正确路由并建实验草稿（修复此前仅精确匹配 bug）' do
            reply = intake.handle(1, msg(text: '/newexp PP配方A'))
            expect(reply).to match(/🆕 已开新实验草稿 #1「PP配方A」/)
            expect(backend.experiments[1][:title]).to eq('PP配方A')
          end

          it '/newexp 带标题与起始日期' do
            reply = intake.handle(1, msg(text: '/newexp 配方B @2026-09-24'))
            expect(reply).to match(/🆕 已开新实验草稿 #1「配方B」/)
            expect(reply).to match(/起始 2026-09-24/)
            expect(backend.experiments[1][:title]).to eq('配方B')
          end

          it '/new 已删除：按普通文本处理，不再建实验' do
            before = backend.experiments.size
            reply = intake.handle(1, msg(text: '/new PP配方A'))
            expect(backend.experiments.size).to eq(before + 1) # 仅 ensure_draft 自动建一条
            expect(backend.experiments.values.last[:title]).to match(/\A微信记录-1\z/)
            expect(reply).not_to match(/🆕 已开新实验草稿/)
          end

          it '/newproject 建项目（含描述）' do
            reply = intake.handle(1, msg(text: '/newproject 中试项目 | 2026Q4 中试'))
            expect(reply).to match(/🆕 已新建项目 #1「中试项目」/)
            expect(backend.projects[1][:name]).to eq('中试项目')
            expect(backend.projects[1][:description]).to eq('2026Q4 中试')
          end

          it '/newproject 起始日期自动填今天' do
            intake.handle(1, msg(text: '/newproject 中试项目'))
            expect(backend.projects[1][:start_date]).to eq(Date.today)
            expect(backend.projects[1][:due_date]).to be_nil
          end

          it '/newproject 可显式指定起始与截止日期' do
            reply = intake.handle(1, msg(text: '/newproject 中试项目 @2026-10-01 ~2026-12-31'))
            expect(backend.projects[1][:start_date]).to eq(Date.new(2026, 10, 1))
            expect(backend.projects[1][:due_date]).to eq(Date.new(2026, 12, 31))
            expect(reply).to match(/起始 2026-10-01，截止 2026-12-31/)
          end

          it '/newproject 名称与描述中的 @提及不被误判为日期' do
            intake.handle(1, msg(text: '/newproject 中试项目 | 负责人 @张三'))
            expect(backend.projects[1][:description]).to eq('负责人 @张三')
            expect(backend.projects[1][:start_date]).to eq(Date.today)
          end

          it '/newproject 缺名称报错' do
            expect(intake.handle(1, msg(text: '/newproject'))).to match(%r{用法：/newproject})
          end

          it '/newtask 在指定实验下建任务并切草稿' do
            eid = backend.create_experiment('E', 'body')
            reply = intake.handle(1, msg(text: "/newtask #{eid} 平行样1 ~2026-10-01"))
            expect(reply).to match(/已在实验 ##{eid} 下新建任务 #1「平行样1」/)
            expect(reply).to match(/截止 2026-10-01/)
            expect(backend.my_modules[1][:experiment_id]).to eq(eid)
            expect(backend.my_modules[1][:name]).to eq('平行样1')
            expect(backend.my_modules[1][:due_date]).to eq(Date.new(2026, 10, 1))
            expect(store.get(1)[:exp_id]).to eq(eid)
          end

          it '/newtask 缺实验ID报错' do
            expect(intake.handle(1, msg(text: '/newtask'))).to match(%r{用法：/newtask})
          end

          it '/newtask 实验ID 非整数报错' do
            expect(intake.handle(1, msg(text: '/newtask abc 任务'))).to match(%r{用法：/newtask})
          end

          it '/listproject 列出可见项目' do
            backend.create_project('P1')
            reply = intake.handle(1, msg(text: '/listproject'))
            expect(reply).to match(/可新建实验的项目（1）/)
            expect(reply).to match(/#1 P1/)
          end

          it '/listproject 空列表提示' do
            expect(intake.handle(1, msg(text: '/listproject'))).to match(/还没有可新建实验的项目/)
          end

          it '/listexp 同 /list 列实验' do
            backend.create_experiment('E1', 'body')
            reply = intake.handle(1, msg(text: '/listexp'))
            expect(reply).to match(/最近的实验/)
          end

          it '/listtask 列出实验下任务' do
            eid = backend.create_experiment('E', 'body')
            backend.create_mymodule(eid, 'T1')
            reply = intake.handle(1, msg(text: "/listtask #{eid}"))
            expect(reply).to match(/实验 ##{eid} 的任务（1）/)
            expect(reply).to match(/#1 T1/)
          end

          it '/listtask 空列表提示' do
            eid = backend.create_experiment('E', 'body')
            reply = intake.handle(1, msg(text: "/listtask #{eid}"))
            expect(reply).to match(/还没有任务/)
          end

          it '/listtask 缺实验ID且无当前实验时报错' do
            expect(intake.handle(1, msg(text: '/listtask'))).to match(%r{用法：/listtask})
          end

          it '/listtask 省略实验ID 时用当前实验' do
            eid = backend.create_experiment('E', 'body')
            intake.handle(1, msg(text: "/setexp #{eid}"))
            backend.create_mymodule(eid, 'T1')
            reply = intake.handle(1, msg(text: '/listtask'))
            expect(reply).to match(/实验 ##{eid} 的任务（1）/)
          end
        end

        context 'Task 级：/settask 与 /gettask' do
          def build_context
            eid = backend.create_experiment('E', 'body', project_id: 1)
            backend.create_project('P1')
            mid = backend.create_mymodule(eid, '平行样1')
            [eid, mid]
          end

          it '/settask 把落点设到任务并同步当前实验' do
            eid, mid = build_context
            reply = intake.handle(1, msg(text: "/settask #{mid}"))
            expect(reply).to match(/当前任务已设为 ##{mid}/)
            expect(store.get(1)[:task_id]).to eq(mid)
            expect(store.get(1)[:exp_id]).to eq(eid)
          end

          it '/settask 后纯文本写入任务正文而非实验正文' do
            eid, mid = build_context
            intake.handle(1, msg(text: "/settask #{mid}"))
            reply = intake.handle(1, msg(text: '今天做了萃取'))
            expect(reply).to match(/已记录到任务 ##{mid}/)
            expect(backend.task_notes[mid].last).to match(/今天做了萃取/)
          end

          it '未 settask 时纯文本仍写实验正文（既有行为不变）' do
            eid, _mid = build_context
            intake.handle(1, msg(text: "/setexp #{eid}"))
            reply = intake.handle(1, msg(text: '今天做了萃取'))
            expect(reply).to match(/已记录到实验 ##{eid}/)
            expect(backend.notes[eid].last).to match(/今天做了萃取/)
          end

          it '/gettask 查看当前任务' do
            _eid, mid = build_context
            intake.handle(1, msg(text: "/settask #{mid}"))
            expect(intake.handle(1, msg(text: '/gettask'))).to match(/当前任务：##{mid}/)
          end

          it '/gettask 无当前任务时给下一步指引' do
            eid, _mid = build_context
            intake.handle(1, msg(text: "/setexp #{eid}"))
            expect(intake.handle(1, msg(text: '/gettask'))).to match(/当前未指定任务/)
          end

          it '/setexp 会退出任务级（避免文本落进别的实验的旧任务）' do
            eid, mid = build_context
            other = backend.create_experiment('E2', 'body')
            intake.handle(1, msg(text: "/settask #{mid}"))
            reply = intake.handle(1, msg(text: "/setexp #{other}"))
            expect(reply).to match(/已退出任务 ##{mid}/)
            expect(store.get(1)[:task_id]).to be_nil
          end

          it '任务不可写时 /settask 拒绝并保持原落点' do
            eid, mid = build_context
            backend.deny_mymodule(mid)
            reply = intake.handle(1, msg(text: "/settask #{mid}"))
            expect(reply).to match(/任务 ##{mid} 不可用/)
            expect(store.get(1)&.fetch(:task_id, nil)).to be_nil
          end

          it '/settask 缺/非法参数给用法提示' do
            expect(intake.handle(1, msg(text: '/settask'))).to match(%r{用法：/settask})
            expect(intake.handle(1, msg(text: '/settask abc'))).to match(%r{用法：/settask})
          end

          it '/done 只收尾实验并提示任务状态流转回 Web 端' do
            eid, mid = build_context
            intake.handle(1, msg(text: "/settask #{mid}"))
            reply = intake.handle(1, msg(text: '/done'))
            expect(reply).to match(/实验 ##{eid} 已收尾/)
            expect(reply).to match(/任务 ##{mid} 未被收尾/)
            expect(backend.completed).to include(eid)
          end
        end

        context '项目作用域：先选项目再建实验（两阶段引导）' do
          let(:state_store) { MemoryUserStateStore.new } # 无预设默认项目

          it '无默认项目时 /newexp 只列可建实验的项目并等待编号，不建实验' do
            backend.create_project('PP配方开发')
            backend.create_project('中试')
            reply = intake.handle(1, msg(text: '/newexp PP配方A @2026-09-24'))
            expect(reply).to match(/请先选一个/)
            expect(reply).to match(/#1 PP配方开发/)
            expect(reply).to match(/#2 中试/)
            expect(backend.experiments).to be_empty
            expect(backend.project_queries.last[:scope]).to eq(:creatable)
          end

          it '回复编号后沿用暂存的标题与日期建实验，并把该项目记住为默认' do
            backend.create_project('PP配方开发')
            backend.create_project('中试')
            intake.handle(1, msg(text: '/newexp PP配方A @2026-09-24 ~2026-10-01'))
            reply = intake.handle(1, msg(text: '2'))
            expect(reply).to match(/默认项目已设为 #2「中试」/)
            expect(reply).to match(/🆕 已开新实验草稿 #3「PP配方A」/)
            exp = backend.experiments[3]
            expect(exp[:project_id]).to eq(2)
            expect(exp[:start_date]).to eq(Date.new(2026, 9, 24))
            expect(exp[:due_date]).to eq(Date.new(2026, 10, 1))
            expect(state_store.default_project_id(1)).to eq(2)
          end

          it '选过一次后再次 /newexp 直接用默认项目，不再问' do
            backend.create_project('PP配方开发')
            intake.handle(1, msg(text: '/newexp'))
            intake.handle(1, msg(text: '1'))
            reply = intake.handle(1, msg(text: '/newexp B'))
            expect(reply).to match(/🆕 已开新实验草稿 #2「B」/)
            expect(backend.experiments[2][:project_id]).to eq(1)
          end

          it '回复 0 取消，不建任何实验' do
            backend.create_project('P1')
            intake.handle(1, msg(text: '/newexp'))
            reply = intake.handle(1, msg(text: '0'))
            expect(reply).to match(/已取消本次新建实验/)
            expect(backend.experiments).to be_empty
            expect(state_store.pending(1)).to be_nil
          end

          it '非编号消息取消 pending 并按普通消息处理（内容不吞）' do
            backend.create_project('P1')
            intake.handle(1, msg(text: '/newexp X'))
            eid = backend.create_experiment('已有', 'body', project_id: 1)
            intake.handle(1, msg(text: "/setexp #{eid}"))
            reply = intake.handle(1, msg(text: '今天做了萃取'))
            expect(reply).to match(/已取消上一条「选择项目」等待/)
            expect(reply).to match(/📝 已记录到 ##{eid}/)
            expect(backend.notes[eid].last).to match(/今天做了萃取/)
          end

          it '无草稿的普通文本也先引导选项目，并把本条内容暂存在 pending' do
            backend.create_project('P1')
            expect(intake.handle(1, msg(text: '今天做了萃取'))).to match(/请先选一个/)
            expect(backend.experiments).to be_empty

            reply = intake.handle(1, msg(text: '1'))
            expect(reply).to match(/🆕 已开新实验草稿/)
            eid = backend.experiments.keys.last
            expect(backend.notes[eid].last).to eq('今天做了萃取')
          end

          it '候选之外的数字按普通消息处理（不当作选择，且不重复弹列表）' do
            backend.create_project('P1')
            intake.handle(1, msg(text: '/newexp X'))
            reply = intake.handle(1, msg(text: '99'))
            expect(reply).to match(/已取消上一条「选择项目」等待/)
            expect(reply).to match(/还没有可用的默认项目/)
            expect(state_store.pending(1)).to be_nil
            expect(backend.experiments).to be_empty
          end

          it 'pending 超时后重新引导' do
            backend.create_project('P1')
            intake.handle(1, msg(text: '/newexp X'))
            state_store.expire_pending!(1)
            expect(intake.handle(1, msg(text: '/newexp Y'))).to match(/请先选一个/)
          end

          it '预设项目失效（无权限/已归档）时清空预设并重新引导' do
            s = MemoryUserStateStore.new.tap { |x| x.set_default_project(1, 7) }
            intake_bad = described_class.new(backend: backend, store: store, state_store: s)
            backend.deny_project(7)
            backend.create_project('P1')
            reply = intake_bad.handle(1, msg(text: '/newexp Z'))
            expect(reply).to match(/原默认项目 #7 已不可用/)
            expect(s.default_project_id(1)).to be_nil
          end

          it '没有任何可建实验的项目时给出明确提示而不空转' do
            expect(intake.handle(1, msg(text: '/newexp'))).to match(/没有任何可新建实验的项目/)
          end
        end

        context '/setproject 与 /project' do
          it '/setproject 设置长期默认项目' do
            backend.create_project('P1')
            reply = intake.handle(1, msg(text: '/setproject 1'))
            expect(reply).to match(/默认项目已设为 #1「P1」/)
            expect(state_store.default_project_id(1)).to eq(1)
          end

          it '/setproject 对不可建实验的项目拒绝' do
            backend.deny_project(9)
            reply = intake.handle(1, msg(text: '/setproject 9'))
            expect(reply).to match(/不可用/)
            expect(state_store.default_project_id(1)).to eq(42) # 保持原值
          end

          it '/setproject 缺参数/非整数给用法' do
            expect(intake.handle(1, msg(text: '/setproject'))).to match(%r{用法：/setproject})
            expect(intake.handle(1, msg(text: '/setproject abc'))).to match(%r{用法：/setproject})
          end

          it '已删除的别名不再被识别为指令' do
            backend.create_project('P1')
            # /useproject 与 /project <ID> 均为已废弃别名，一律应按普通文本录入
            expect(intake.handle(1, msg(text: '/useproject 1'))).not_to match(/默认项目已设为/)
            expect(intake.handle(1, msg(text: '/project 1'))).not_to match(/默认项目已设为/)
            expect(intake.handle(1, msg(text: '/list'))).not_to match(/最近的实验/)
          end

          it '/getproject 显示当前默认项目' do
            backend.create_project('P1')
            intake.handle(1, msg(text: '/setproject 1'))
            expect(intake.handle(1, msg(text: '/getproject'))).to match(/当前默认项目：#1「P1」/)
          end

          it '/getproject 未设置时引导设置' do
            i = described_class.new(backend: backend, store: store, state_store: MemoryUserStateStore.new)
            expect(i.handle(1, msg(text: '/getproject'))).to match(/当前未设置默认项目/)
          end

          it '已重命名的 /project 不再显示默认项目（按普通文本录入）' do
            backend.create_project('P1')
            intake.handle(1, msg(text: '/setproject 1'))
            expect(intake.handle(1, msg(text: '/project'))).not_to match(/当前默认项目：/)
          end
        end

        context '/listproject 作用域' do
          it '默认只列可建实验的项目，不列只读项目' do
            backend.create_project('可建')
            backend.create_project('只读', read_only: true)
            reply = intake.handle(1, msg(text: '/listproject'))
            expect(reply).to match(/可新建实验的项目（1）/)
            expect(reply).to match(/#1 可建/)
            expect(reply).not_to match(/只读/)
            expect(backend.project_queries.last[:scope]).to eq(:creatable)
          end

          it 'all 列出全部可读项目（含只读）' do
            backend.create_project('可建')
            backend.create_project('只读', read_only: true)
            reply = intake.handle(1, msg(text: '/listproject all'))
            expect(reply).to match(/可见项目（含只读）（2）/)
            expect(backend.project_queries.last[:scope]).to eq(:readable)
          end
        end

        context '/setexp 同步默认项目' do
          it '切到某实验即把它的所属项目设为默认项目' do
            eid = backend.create_experiment('E', 'body', project_id: 5)
            intake.handle(1, msg(text: "/setexp #{eid}"))
            expect(state_store.default_project_id(1)).to eq(5)
          end

          it '所属项目不可建实验时不设为默认，并给出提示' do
            backend.deny_project(6)
            eid = backend.create_experiment('E', 'body', project_id: 6)
            reply = intake.handle(1, msg(text: "/setexp #{eid}"))
            expect(reply).to match(/没有「创建实验」权限/)
            expect(state_store.default_project_id(1)).to eq(42)
          end
        end
      end
    end
  end
end
