-- =====================================================================
--  AJUSTES: frete de produtos físicos + controle de envio do pedido
--  (rodar DEPOIS de db/03_tipos_produto.sql)
-- =====================================================================

-- valor fixo de frete por produto (usado só nos produtos físicos)
alter table public.produtos
  add column if not exists frete numeric(10,2) not null default 0;

-- controle de envio do pedido (para livros físicos)
alter table public.pedidos
  add column if not exists enviado boolean not null default false,
  add column if not exists rastreio text;

-- permite que o ADMIN atualize os pedidos pelo painel (marcar como enviado,
-- adicionar código de rastreio). A criação continua via Edge Function.
drop policy if exists "pedidos admin atualiza" on public.pedidos;
create policy "pedidos admin atualiza" on public.pedidos
  for update to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- Fim.
