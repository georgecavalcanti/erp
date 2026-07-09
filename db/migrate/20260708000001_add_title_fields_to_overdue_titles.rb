class AddTitleFieldsToOverdueTitles < ActiveRecord::Migration[8.1]
  def change
    # Do export detalhado por título (Consulta de Títulos do Sankhya):
    add_column :overdue_titles, :external_uid, :bigint    # Nro Único -> liga à nota
    add_column :overdue_titles, :days_overdue, :integer    # Atraso (dias), já calculado pelo ERP
    add_column :overdue_titles, :title_type, :string       # Descrição (Tipo de Título): BOLETO/PIX...

    add_index :overdue_titles, :external_uid
  end
end
