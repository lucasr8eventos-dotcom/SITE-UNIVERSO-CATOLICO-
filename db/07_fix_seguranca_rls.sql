-- =====================================================================
--  07 — Correções de segurança (RLS/Storage e vínculo de acessos)
--  Rode DEPOIS do 06. Depende de public.eh_admin() (criada no 02).
--
--  O que este arquivo conserta:
--   1) Escrita em categorias/livros/atividades estava liberada para
--      QUALQUER usuário autenticado (to authenticated using(true)).
--      -> agora só admin (public.eh_admin()).
--   2) Bucket público "midia": upload/alteração/exclusão estava liberado
--      para qualquer usuário autenticado. -> agora só admin.
--   3) Vínculo de acessos por e-mail acontecia no cadastro, ANTES de
--      confirmar o e-mail (risco de herdar a compra de outra pessoa).
--      -> agora só vincula quando o e-mail está confirmado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Escrita nas tabelas de conteúdo: apenas ADMIN
-- ---------------------------------------------------------------------
drop policy if exists "escrita admin categorias" on public.categorias;
create policy "escrita admin categorias" on public.categorias
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists "escrita admin livros" on public.livros;
create policy "escrita admin livros" on public.livros
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists "escrita admin atividades" on public.atividades;
create policy "escrita admin atividades" on public.atividades
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- ---------------------------------------------------------------------
-- 2) Bucket público "midia": só ADMIN pode enviar/alterar/excluir
--    (leitura continua pública)
-- ---------------------------------------------------------------------
drop policy if exists "midia upload admin" on storage.objects;
create policy "midia upload admin" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'midia' and public.eh_admin());

drop policy if exists "midia update admin" on storage.objects;
create policy "midia update admin" on storage.objects
  for update to authenticated
  using (bucket_id = 'midia' and public.eh_admin())
  with check (bucket_id = 'midia' and public.eh_admin());

drop policy if exists "midia delete admin" on storage.objects;
create policy "midia delete admin" on storage.objects
  for delete to authenticated
  using (bucket_id = 'midia' and public.eh_admin());

-- ---------------------------------------------------------------------
-- 3) Vínculo de acessos só com e-mail CONFIRMADO
--    (se a confirmação de e-mail estiver desligada no Supabase, o
--     email_confirmed_at já vem preenchido no insert, então continua
--     funcionando na hora do cadastro)
-- ---------------------------------------------------------------------
create or replace function public.vincular_acessos_novo_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.email_confirmed_at is not null then
    update public.acessos set user_id = new.id
    where user_id is null and lower(email) = lower(new.email);
  end if;
  return new;
end; $$;

drop trigger if exists trg_vincular_acessos on auth.users;
create trigger trg_vincular_acessos
  after insert or update of email_confirmed_at on auth.users
  for each row execute function public.vincular_acessos_novo_usuario();

-- Fim.
