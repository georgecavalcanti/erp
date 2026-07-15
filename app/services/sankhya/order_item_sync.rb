module Sankhya
  # Itens dos PEDIDOS (TOP 1001) -> OrderItem, com consolidação de margem no
  # pedido. Mecânica na base Sankhya::ItemSync.
  #
  #   Sankhya::OrderItemSync.new(since: Date.new(2024, 12, 1)).call  # backfill
  #   Sankhya::OrderItemSync.new(changed_within_hours: 24).call      # incremental
  class OrderItemSync < ItemSync
    TOPS = [ 1001 ].freeze

    private

    def tops = TOPS
    def item_class = OrderItem
    def parent_class = Order
    def parent_fk = :order_id
    def parent_table = "orders"
    def item_table = "order_items"
  end
end
