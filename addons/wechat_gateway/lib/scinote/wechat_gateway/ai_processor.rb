# frozen_string_literal: true

require 'json'

module Scinote
  module WechatGateway
    # AI 结构化抽取（F12，增强，Ticket 06）：自由文本 -> 固定 schema（配方）。
    # LLM（OpenAI 兼容，JSON mode）可注入：extract(text, llm:)；未配置端点即禁用。
    # GLP：原文完整保留 + 标「AI 辅助整理 · 需人工审核」，默认只写草稿（plan §12.3）。
    module AiProcessor
      Component = Struct.new(:name, :amount, :unit, keyword_init: true)
      ResultItem = Struct.new(:property, :value, :unit, keyword_init: true)
      StructuredRecord = Struct.new(
        :experiment_title, :type, :components, :process_params, :results, :notes,
        keyword_init: true
      ) do
        def components = self[:components] || []
        def results = self[:results] || []
        def process_params = self[:process_params] || {}
      end

      PROMPT = '你是材料科学实验记录助手。把实验员的自由描述抽取为 JSON，字段：' \
               'experiment_title(字符串), type(配方实验/测试/其他), ' \
               'components(数组:{name,amount,unit}), process_params(对象), ' \
               'results(数组:{property,value,unit}), notes(字符串)。只输出 JSON，不要解释。'

      class << self
        def enabled?
          Scinote::WechatGateway.configuration.ai_enabled.present? &&
            Scinote::WechatGateway.configuration.ai_endpoint.present?
        end

        # text -> StructuredRecord | nil（失败返回 nil，调用方降级为原文落库）
        # llm: callable(text) -> JSON String | Hash | StructuredRecord；缺省用 default_llm
        def extract(text, llm: nil)
          llm ||= default_llm
          return nil unless llm

          out = llm.call(text)
          out.is_a?(StructuredRecord) ? out : parse(out)
        rescue StandardError => e
          warn_log("ai extract failed: #{e.message}")
          nil
        end

        # JSON 字符串 / Hash -> StructuredRecord（解析失败返回 nil）
        def parse(json)
          data = json.is_a?(Hash) ? json : JSON.parse(json.to_s)
          StructuredRecord.new(
            experiment_title: data['experiment_title'].to_s,
            type: (data['type'].presence || '配方实验').to_s,
            components: Array(data['components']).map do |c|
              Component.new(name: c['name'].to_s, amount: c['amount'], unit: c['unit'])
            end,
            process_params: (data['process_params'] || {}),
            results: Array(data['results']).map do |r|
              ResultItem.new(property: r['property'].to_s, value: r['value'], unit: r['unit'])
            end,
            notes: data['notes'].to_s
          )
        rescue JSON::ParserError, TypeError
          nil
        end

        # GLP 正文：原文 + AI 整理块（标需人工审核）
        def format_body(raw_text, record)
          lines = ['【原始消息】', raw_text.to_s.strip, '', '【AI 辅助整理 · 需人工审核】']
          lines << "标题：#{record.experiment_title}" if record.experiment_title.present?
          if record.components.any?
            comp = record.components.map { |c| "#{c.name} #{c.amount || '?'}#{c.unit}" }.join('；')
            lines << "配方组成：#{comp}"
          end
          if record.process_params.present?
            lines << '工艺参数：' + record.process_params.map { |k, v| "#{k}=#{v}" }.join('；')
          end
          if record.results.any?
            results = record.results.map { |r| "#{r.property} #{r.value || '?'}#{r.unit}" }.join('；')
            lines << "测试结果：#{results}"
          end
          lines << "备注：#{record.notes}" if record.notes.present?
          lines.join("\n")
        end

        def default_llm
          return nil unless enabled?

          ->(text) { http_complete(text) }
        end

        def http_complete(text)
          require 'uri'
          require 'net/http'
          uri = URI(Scinote::WechatGateway.configuration.ai_endpoint)
          req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
          key = Scinote::WechatGateway.configuration.ai_api_key
          req['Authorization'] = "Bearer #{key}" if key.present?
          req.body = {
            model: Scinote::WechatGateway.configuration.ai_model,
            response_format: { type: 'json_object' },
            messages: [{ role: 'system', content: PROMPT }, { role: 'user', content: text }]
          }.to_json
          res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
          JSON.parse(res.body).dig('choices', 0, 'message', 'content').to_s
        end

        def warn_log(msg)
          Rails.logger.warn("[wechat_gateway] #{msg}") if defined?(Rails)
        end
      end
    end
  end
end
