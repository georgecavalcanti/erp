require "csv"

# Exportações controladas e registradas (doc 09): exportar dados exige perfil
# gestor+ e cada exportação vira um ExportLog (quem, o quê, nº de linhas, filtros).
module Exportable
  extend ActiveSupport::Concern

  # BOM UTF-8: faz o Excel pt-BR abrir o CSV com acentuação correta.
  BOM = "﻿".freeze

  private

  # Barreira de perfil das exportações — gestor comercial + admin (doc 09).
  # Usada em `before_action ..., only: :export` nas telas que exportam.
  def require_exporter
    return if Current.user&.manages_commercial?

    redirect_to root_path, alert: "Exportação restrita à gestão comercial."
  end

  # Gera o CSV (`;` + BOM p/ Excel pt-BR), REGISTRA a exportação e envia o arquivo.
  # Chamado só depois de require_exporter.
  def send_registered_csv(kind:, filename:, headers:, rows:, filters: {})
    csv = CSV.generate(col_sep: ";") do |out|
      out << headers
      rows.each { |row| out << row }
    end
    ExportLog.create!(user: Current.user, kind: kind, format: "csv", row_count: rows.size, filters: filters)
    send_data "#{BOM}#{csv}", filename: filename, type: "text/csv; charset=utf-8"
  end
end
