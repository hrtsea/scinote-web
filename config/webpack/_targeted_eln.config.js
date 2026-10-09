// 定向构建（**容器内**运行；只编指定 entry，输出沿用基础配置的 app/assets/builds）。
//
// 为什么需要：本容器全量 webpack（~110 entry）会打爆 Docker API（全 500），
//   故一律只编目标 entry。此配置**不覆盖 output** ⇒ 产物落 app/assets/builds/<name>.js|css，
//   余下 entry 的既有产物原样保留（基础配置 output 无 clean）。
//
// 用法（容器内，root）：
//   ENTRIES=eln_project_list NODE_ENV=production \
//     ./node_modules/.bin/webpack --config config/webpack/_targeted_eln.config.js
const baseConfig = require('./webpack.config.js');

const names = (process.env.ENTRIES || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

if (names.length === 0) {
  throw new Error('ENTRIES 未指定');
}

const entry = {};
names.forEach((n) => {
  if (!baseConfig.entry[n]) {
    throw new Error('未知 entry: ' + n);
  }
  entry[n] = baseConfig.entry[n];
});

module.exports = Object.assign({}, baseConfig, { entry });
