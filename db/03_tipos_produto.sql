-- =====================================================================
--  AJUSTES: tipos de produto + endereço de entrega
--  (rodar DEPOIS de db/02_loja_membros.sql)
--
--  Tipos de produto:
--    'infoproduto' -> tem PDFs; libera acesso na área de membros após pagar
--    'fisico'      -> livro físico; vendido no site (precisa de endereço)
--    'externo'     -> divulgação com link externo (ex.: Amazon), sem checkout
-- =====================================================================

alter table public.produtos
  add column if not exists tipo text not null default 'infoproduto',
  add column if not exists descricao_curta text,
  add column if not exists link_externo text;

-- garante valores válidos
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'produtos_tipo_check'
  ) then
    alter table public.produtos
      add constraint produtos_tipo_check
      check (tipo in ('infoproduto','fisico','externo'));
  end if;
end $$;

-- endereço de entrega (para livros físicos), guardado junto do pedido
alter table public.pedidos
  add column if not exists endereco jsonb;

-- View com estatísticas de vendas (útil para o painel do admin)
create or replace view public.vw_vendas as
select
  p.id            as pedido_id,
  p.criado_em,
  p.email,
  p.nome,
  p.valor,
  p.status,
  pr.nome         as produto_nome,
  pr.tipo         as produto_tipo
from public.pedidos p
left join public.produtos pr on pr.id = p.produto_id;

-- Fim.
