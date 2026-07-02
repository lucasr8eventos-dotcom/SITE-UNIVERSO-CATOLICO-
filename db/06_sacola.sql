-- =====================================================================
--  SACOLA (carrinho): um pedido pode ter VÁRIOS produtos
--  (rodar DEPOIS de db/02_loja_membros.sql)
--
--  Guardamos os itens do pedido como JSON na própria linha do pedido.
--  Cada item: { produto_id, nome, preco, tipo, quantidade }.
--  O campo produto_id do pedido continua preenchido (com o 1º item) só
--  para compatibilidade com telas/relatórios antigos.
-- =====================================================================

alter table public.pedidos
  add column if not exists itens jsonb;

-- Fim.
