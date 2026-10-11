#!/bin/bash
# ELN UI 代码落地到运行中容器（宿主机 Windows Git Bash 环境）
#
# ⚠ 为什么不用现成的 sync_eln_ui.sh：本轮需要同步的范围**跨了 addon 边界** ——
#   eln_ui 源码 + 宿主 webpack 配置 + 宿主 assets 登记 + 宿主新 pack 入口 + 路由 + teams 视图。
#   那个脚本只管 addons/eln_ui/**，且它默认 web+jobs 两台（jobs 侧无必要）。
#
# ⚠ 路径纪律（本轮踩过的坑）：容器工作目录是 /usr/src/app，宿主机路径是
#   F:/elndev/scinote-web（本轮会话开始时它还叫 F:/eln开发/，被重命名过 —— 别硬编码目录名，
#   一律用 pwd 取）。所有 docker cp 都必须带 MSYS_NO_PATHCONV=1，否则 Git Bash 会把
#   容器内绝对路径当成本地 Windows 路径转换掉（曾报 "invalid output path: C:\tmp"）。
#
# ⚠ 绝不用 `docker cp app scinote_web_production:/usr/src/app/app` 这类「整目录」写法：
#   目标已存在时 docker cp 的语义是把**源目录名追加**到目标目录下 =>
#   /usr/src/app/app + app => /usr/src/app/app/app，整个 app/ 副本（264MB/2584 文件）
#   落进 eager load 扫描范围 ⇒ Zeitwerk::NameError ⇒ 容器起不来。
#   本脚本只逐文件 cp。
set -euo pipefail

CONTAINER="${CONTAINER:-scinote_web_production}"
# ⚠ 必须用 Windows 绝对路径给 docker cp：Git Bash 的 pwd 返回 /f/... 风格，
#   docker cp 会把它当本地相对路径 ⇒ "CreateFile F:\f: The system cannot find the file"。
ROOT="$(pwd -W 2>/dev/null || pwd)"
N=0

echo "容器: $CONTAINER   宿主根: $ROOT"

# 1) eln_ui 下所有新增/修改的源码（含未跟踪的迁移、模型、视图、blob）
#    ⚠ 新增文件的目标目录在容器里可能不存在（重建容器后只有镜像里的目录树），
#      docker cp 不会自动创建父目录 ⇒ 先 mkdir -p 再cp。
while read -r f; do
  [ -f "$ROOT/$f" ] || continue
  MSYS_NO_PATHCONV=1 docker exec "$CONTAINER" mkdir -p "/usr/src/app/$(dirname "$f")" >/dev/null
  MSYS_NO_PATHCONV=1 docker cp "$ROOT/$f" "$CONTAINER:/usr/src/app/$f" >/dev/null
  N=$((N+1))
done < <(git status -uall --short -- addons/eln_ui | awk '$1=="M"||$1=="??"||$1=="A"{print $2}')

# 2) 宿主机侧必须一起动的文件（webpack entry 表 / precompile 登记 / 路由 / teams 页）
#    ⚠ 列表要覆盖**新增组件**，不只是入口文件：teams_table.js / team_new.js import
#      app/javascript/vue/teams/{table,new_form}.vue 与 renderers/*，漏同步 ⇒ webpack
#      报 "xxx.vue doesn't exist / Field 'browser' doesn't contain a valid alias"。
#      这里用 git status 兜住所有 teams 相关新增/修改文件，比逐个列举可靠。
for f in \
  config/webpack/webpack.config.js \
  config/initializers/assets.rb \
  config/routes.rb \
  app/javascript/packs/vue/team_new.js \
  app/javascript/packs/vue/teams_table.js \
  app/javascript/packs/vue/helpers/turbolinks.js \
  app/javascript/vue/team_preferences/container.vue \
  app/views/users/settings/teams/show.html.erb \
  app/views/users/settings/teams/new.html.erb
do
  [ -f "$ROOT/$f" ] || { echo "  跳过（不存在）: $f"; continue; }
  MSYS_NO_PATHCONV=1 docker exec "$CONTAINER" mkdir -p "/usr/src/app/$(dirname "$f")" >/dev/null
  MSYS_NO_PATHCONV=1 docker cp "$ROOT/$f" "$CONTAINER:/usr/src/app/$f" >/dev/null
  N=$((N+1))
done

# 2b) 宿主 app/javascript/vue/teams/** 下所有新增/修改（ADR-0034 工作区列表 Vue 化）
while read -r f; do
  [ -f "$ROOT/$f" ] || continue
  MSYS_NO_PATHCONV=1 docker exec "$CONTAINER" mkdir -p "/usr/src/app/$(dirname "$f")" >/dev/null
  MSYS_NO_PATHCONV=1 docker cp "$ROOT/$f" "$CONTAINER:/usr/src/app/$f" >/dev/null
  N=$((N+1))
done < <(git status -uall --short -- app/javascript/vue/teams | awk '$1=="M"||$1=="??"||$1=="A"||$1=="AM"{print $NF}')

# 3) 宿主侧删除的文件同步删除（源码已迁走的旧 pack / 旧 teams 组件）
while read -r f; do
  MSYS_NO_PATHCONV=1 docker exec "$CONTAINER" rm -f "/usr/src/app/$f" >/dev/null 2>&1 || true
  echo "  删除: $f"
done < <(git status -uall --short -- addons/eln_ui | awk '$1=="D"{print $2}')

echo "已同步 $N 个文件 + 上述删除"
echo
echo "下一步："
echo "  docker exec $CONTAINER sh -lc 'cd /usr/src/app && ENTRIES=<entry1,entry2> NODE_ENV=production ./node_modules/.bin/webpack --config config/webpack/_targeted_eln.config.js'"
echo "  docker exec $CONTAINER sh -lc 'cd /usr/src/app && SKIP_ACCESS_CONTROL_DB_CHECK=1 SECRET_KEY_BASE=dummy bundle exec rails assets:precompile'"
echo "  docker restart $CONTAINER"
