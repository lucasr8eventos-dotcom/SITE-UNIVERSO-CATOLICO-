-- =====================================================================
--  CORREÇÃO: quem comprou deve continuar vendo o produto mesmo que ele
--  seja desativado na loja (produto inativo não some da área do cliente).
--  (rodar DEPOIS de db/04_frete_envio.sql)
-- =====================================================================

drop policy if exists "produtos leitura publica" on public.produtos;
create policy "produtos leitura publica" on public.produtos
  for select using (
    ativo = true
    or public.eh_admin()
    or public.tem_acesso(id)   -- comprador vê o que comprou, mesmo inativo
  );

-- Fim.
