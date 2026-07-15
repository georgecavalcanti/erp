# Cria (ou atualiza) o usuário administrador para acesso ao painel.
# Sobrescreva via variáveis de ambiente: ADMIN_EMAIL / ADMIN_PASSWORD.
admin_email = ENV.fetch("ADMIN_EMAIL", "admin@faturamento.local")
admin_password = ENV.fetch("ADMIN_PASSWORD", "faturamento123")

admin = User.find_or_initialize_by(email_address: admin_email)
admin.password = admin_password
admin.role = :administrador # sem isto cairia no default (vendedor), que exige salesperson_id
admin.save!

puts "== Admin pronto =="
puts "   e-mail: #{admin_email}"
puts "   senha:  #{admin_password}"
