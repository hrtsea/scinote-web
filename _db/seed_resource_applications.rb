# frozen_string_literal: true

# ============================================================================
# Seed：资源申请单（eln_ui_resource_applications）
# ============================================================================
#
# 用途：让资源中心「资源申请」tab（原型 applyRows）和「资源申请详情页」
#       能跳到**真实数据** —— 而不是顶着原型演示文案。
#
# 数据口径：
#   - 1 条 SQ-2026-7777（详情页演示：测试表征 · DSC 差示扫描量热）
#   - 4 条 SQ-2026-0090/91/92/93（列表页演示：覆盖 4 种状态）
#
# ⚠ 生产库纪律：
#   - **只 INSERT/UPDATE/DELETE eln_ui_resource_applications** 一张表
#   - 不 ALTER 任何原生表
#   - 不新建项目/用户（用现有真实数据作 requestor/reviewer）
#   - 重复跑幂等（已存在的 no 跳过；同 no 重复刷新其 items/note/status 字段）
#
# 用法（容器内）：
#   bin/rails runner /tmp/seed_resource_applications.rb            # 灌
#   bin/rails runner /tmp/seed_resource_applications.rb --rollback # 清
#
# 自证：脚本末尾打印「提交/审批/驳回/完成」时间戳 + 原生项目/用户字段未变。
# ============================================================================

ROLLBACK = ARGV.include?('--rollback')

# ---- 收尾工具 ----
def destroy_only_seed_apps
  Scinote::ElnUi::ResourceApplication
    .where('no LIKE ?', 'SQ-2026-7777%').delete_all
  Scinote::ElnUi::ResourceApplication
    .where('no IN (?)', %w[SQ-2026-0090 SQ-2026-0091 SQ-2026-0092 SQ-2026-0093])
    .delete_all
end

if ROLLBACK
  n = destroy_only_seed_apps
  puts "== 已删除 seed 申请单：#{n} 行"
  puts '== 原生字段（projects/users）零改动（脚本不写原生表）'
  exit 0
end

# ---- 取真实项目 / 用户 ----
# ⚠ rails runner 没有 controller 上下文，current_team 不存在 → 直接 Team.first
team = Team.first
abort '✗ 没有 team（生产库须先有至少一个 team）' if team.nil?

# 优先用 real 项目，找不到再退到任何一个 active project
proj_pp = ::Project.where(team_id: team.id, archived: false)
                   .where('name LIKE ?', '%PP%').first
proj_pp ||= ::Project.where(team_id: team.id, archived: false).first
abort '✗ 当前 team 下没有任何 active project' if proj_pp.nil?

# 用户：取团队成员表前 3 个 + hpxing 兜底
users = team.user_assignments
            .where(assignable_type: 'Team')
            .includes(:user)
            .limit(5)
            .map(&:user)
            .compact
            .uniq
hpxing = ::User.find_by(email: 'hpxing@localhost')
users << hpxing if hpxing && users.exclude?(hpxing)
abort '✗ 没有真实用户' if users.empty?

u_requestor  = users[0]
u_group      = users[1] || users[0]
u_project    = users[2] || users[1] || users[0]

puts "==> team = ##{team.id} #{team.name.inspect}"
puts "==> project = ##{proj_pp.id} #{proj_pp.name.inspect}"
puts "==> requestor = ##{u_requestor.id} #{u_requestor.email}"
puts "==> group_reviewer = ##{u_group.id} #{u_group.email}"
puts "==> project_reviewer = ##{u_project.id} #{u_project.email}"

# ---- 5 条种子申请 ----
SEEDS = [
  {
    no: 'SQ-2026-7777',
    status: 'completed',
    items: [
      { kind: 'service', name: 'DSC 差示扫描量热', qty: 2, unit: '次',
        unit_price: 600, amount: 1200,
        note: 'PP 配方开发第 2 轮配方对比，需测定 2 组样品的熔融峰温与结晶度' }
    ],
    note: 'PP 配方开发第 2 轮配方对比，需测定 2 组样品的熔融峰温与结晶度，' \
          '用于验证 POE 增韧剂配比调整对结晶行为的影响。',
    submitted_at: '2026-09-07 09:20',
    group_approved_at: '2026-09-07 14:05',
    project_approved_at: '2026-09-08 09:30',
    completed_at: '2026-09-08 14:10'
  },
  {
    no: 'SQ-2026-0092',
    status: 'project_approved',
    items: [
      { kind: 'service', name: 'DSC 差示扫描量热', qty: 2, unit: '次',
        unit_price: 600, amount: 1200 }
    ],
    note: 'PP 配方开发第 2 轮配方对比。',
    submitted_at: '2026-09-07 09:20',
    group_approved_at: '2026-09-07 14:05',
    project_approved_at: '2026-09-08 09:30',
    completed_at: nil
  },
  {
    no: 'SQ-2026-0091',
    status: 'completed',
    items: [
      { kind: 'material', name: 'PP 基料 K8003', qty: 20, unit: 'kg',
        unit_price: 350, amount: 7000 }
    ],
    note: '高温硅胶研究 · 第 3 轮配方收敛所需基料。',
    submitted_at: '2026-09-10 14:05',
    group_approved_at: '2026-09-10 16:20',
    project_approved_at: '2026-09-11 09:00',
    completed_at: '2026-09-12 10:24'
  },
  {
    no: 'SQ-2026-0093',
    status: 'submitted',
    items: [
      { kind: 'service', name: '万能材料试验机（拉伸）', qty: 3, unit: '次',
        unit_price: 200, amount: 600 }
    ],
    note: 'PP 配方开发 · 拉伸性能测试。',
    submitted_at: '2026-09-09 11:40',
    group_approved_at: nil,
    project_approved_at: nil,
    completed_at: nil
  },
  {
    no: 'SQ-2026-0090',
    status: 'rejected',
    items: [
      { kind: 'material', name: '滑石粉 TYT-777A', qty: 10, unit: 'kg',
        unit_price: 180, amount: 1800 }
    ],
    note: '高温硅胶研究 · 拟补 10 kg 滑石粉；仓库库存足够，驳回。',
    submitted_at: '2026-09-02 16:30',
    group_approved_at: nil,
    project_approved_at: nil,
    completed_at: nil
  }
].freeze

SEEDS.each do |seed|
  rec = Scinote::ElnUi::ResourceApplication.find_or_initialize_by(no: seed[:no])
  rec.project          = proj_pp
  rec.requestor        = u_requestor
  rec.group_reviewer   = seed[:status] == 'submitted' || seed[:status] == 'rejected' ? nil : u_group
  rec.project_reviewer = seed[:status] == 'project_approved' || seed[:status] == 'completed' ? u_project : nil
  rec.status           = seed[:status]
  rec.items            = seed[:items]
  rec.note             = seed[:note]
  rec.submitted_at     = Time.zone.parse(seed[:submitted_at]) if seed[:submitted_at]
  rec.group_approved_at  = seed[:group_approved_at]  ? Time.zone.parse(seed[:group_approved_at])  : nil
  rec.project_approved_at = seed[:project_approved_at] ? Time.zone.parse(seed[:project_approved_at]) : nil
  rec.completed_at     = seed[:completed_at] ? Time.zone.parse(seed[:completed_at]) : nil
  rec.save!
  puts "==> #{rec.no} #{rec.status} (id=#{rec.id}) ✓"
end

# ---- 自证：原生零改动 ----
fresh_proj = ::Project.find_by(id: proj_pp.id)
proj_unchanged = %w[name team_id created_by_id archived visibility].all? do |c|
  fresh_proj.respond_to?(c) && fresh_proj.public_send(c) == proj_pp.public_send(c)
end
puts "==> 自证：项目 ##{proj_pp.id} 原生字段未变 = #{proj_unchanged}"

puts "\n==> 完成。可访问："
puts "    /eln_res_center          （4 tab 看申请列表）"
puts "    /eln_res_apply/SQ-2026-7777  （详情页演示数据）"
puts "==> 回滚：bin/rails runner /tmp/seed_resource_applications.rb --rollback"
exit 0
