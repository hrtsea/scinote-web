# frozen_string_literal: true

class LabelTemplatesPreviewService
  extend Service

  attr_reader :error, :preview

  def initialize(params, user)
    @user = user
    @params = params
  end

  def generate_zpl_preview!
    if ENV['LABEL_PREVIEW_URL'].present?
      generate_zpl_preview_from_url!
    elsif ENV['LABEL_PREVIEW_AWS_LAMBDA'].present?
      generate_zpl_preview_from_lambda!
    else
      # 二开（2026-10-08）：本环境无 AWS 凭证，原 Lambda 分支必然抛 MissingRegionError → 500。
      # 容器实测可直达 Labelary 公共 API，故默认走 Labelary；需要 Lambda 时显式设 LABEL_PREVIEW_AWS_LAMBDA=1。
      generate_zpl_preview_from_labelary!
    end
  end

  private

  def generate_zpl_preview_from_url!
    resp = HTTParty.post(
      ENV['LABEL_PREVIEW_URL'],
      body: {
        content: @params[:zpl],
        width: @params[:width],
        height: @params[:height],
        density: @params[:density]
      }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    if resp.success?
      @preview = resp.body
    else
      @error = resp.body.presence || I18n.t('label_templates.label_preview.error_html')
    end
  rescue StandardError => e
    @error = e.message
  end

  # Labelary 公共渲染 API：POST ZPL 文本 → PNG。
  # 前端 width/height 传毫米（label_preview.vue emit 的是 mm），Labelary 尺寸单位是英寸。
  # controller 侧取 generate_zpl_preview!.split.last 作为 base64，故这里带 data URI 前缀且用 strict_encode64（无换行）。
  def generate_zpl_preview_from_labelary!
    dpmm   = @params[:density].to_i
    width  = (@params[:width].to_f / 25.4).round(3)
    height = (@params[:height].to_f / 25.4).round(3)
    zpl    = @params[:zpl].to_s
    url = "http://api.labelary.com/v1/printers/#{dpmm}dpmm/labels/#{width}x#{height}/0/"

    resp = HTTParty.post(url, body: zpl, headers: { 'Accept' => 'image/png' }, timeout: 15)

    if resp.success?
      # 注意：组件模板自己拼 data URI 前缀（label_preview.vue 的 :src="`data:image/png;base64,${base64Image}`"），
      # 这里只返回纯 base64 —— 带前缀会双重拼接导致 <img> 加载失败（naturalWidth=0）。
      @preview = Base64.strict_encode64(resp.body)
    else
      @error = "Labelary HTTP #{resp.code}: #{resp.body.to_s[0, 200]}"
    end
  rescue StandardError => e
    @error = e.message
  end

  def generate_zpl_preview_from_lambda!
    client = Aws::Lambda::Client.new(region: ENV['AWS_REGION'])
    resp = client.invoke(
      function_name: 'BinaryKitsZplViewer',
      invocation_type: 'RequestResponse',
      log_type: 'Tail',
      payload:
        "{ \"content\": #{@params[:zpl].to_json},"\
        "\"width\": #{@params[:width]},"\
        "\"height\": #{@params[:height]},"\
        "\"density\": #{@params[:density]} "\
        "}"
    )

    if resp.function_error.nil?
      @preview = resp.payload.string.delete('"')
    else
      begin
        error_response = JSON.parse(resp.payload.string)
        @error = error_response['errorMessage']
      rescue JSON::ParserError
        @error = resp.function_error
      end
    end
  end
end
