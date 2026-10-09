// 定向构建配置：只编 ai_protocol_parser 这一个 entry（避开全量 ~110 entry 的 Docker API 雷区）。
// 用法（容器内）：
//   NODE_ENV=production ./node_modules/.bin/webpack --config config/webpack/_ai_parser_build.config.js
const baseConfig = require('./webpack.config.js');

if (!baseConfig.entry['ai_protocol_parser']) {
  throw new Error('未找到 entry: ai_protocol_parser');
}

module.exports = Object.assign({}, baseConfig, {
  entry: { ai_protocol_parser: baseConfig.entry['ai_protocol_parser'] },
  output: Object.assign({}, baseConfig.output, {
    path: '/usr/src/app/app/assets/builds'
  })
});
