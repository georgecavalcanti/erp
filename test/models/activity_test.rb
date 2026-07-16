require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  # Regressão (review): atividade é histórico. Remover o usuário deve PRESERVAR a
  # atividade (anulando só a autoria), não apagá-la em cascata.
  test "remover o usuário preserva a atividade e anula a autoria" do
    sp = Salesperson.create!(external_code: 5501, nickname: "V")
    partner = Partner.create!(external_code: 5601, name: "CLIENTE")
    user = User.create!(email_address: "u@x.com", password: "secret123", role: :vendedor, salesperson: sp)
    act = Activity.create!(user: user, partner: partner, kind: :contact, occurred_at: Time.current)

    user.destroy

    act.reload
    assert_nil act.user_id                  # autoria anulada
    assert_equal partner.id, act.partner_id # atividade preservada
  end
end
