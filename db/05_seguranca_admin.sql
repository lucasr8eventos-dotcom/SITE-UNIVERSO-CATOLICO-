-- =====================================================================
--  CORREÇÃO DE SEGURANÇA — escrita restrita a ADMIN (não "autenticado")
--  (rodar DEPOIS de db/02_loja_membros.sql — usa public.eh_admin())
--
--  PROBLEMA CORRIGIDO:
--  As políticas originais de categorias/livros/atividades e do bucket
--  público "midia" liberavam escrita para QUALQUER usuário autenticado
--  (using(true)). Como a loja agora cria contas de CLIENTES, um cliente
--  logado poderia alterar o catálogo ou subir/apagar arquivos. Aqui
--  passamos a exigir que o usuário seja admin de verdade (eh_admin()).
--
--  A leitura pública continua igual (o site precisa mostrar o conteúdo).
-- =====================================================================

-- ---- CATEGORIAS / LIVROS / ATIVIDADES: só admin escreve ----
drop policy if exists "escrita admin categorias" on public.categorias;
create policy "escrita admin categorias" on public.categorias
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists "escrita admin livros" on public.livros;
create policy "escrita admin livros" on public.livros
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists "escrita admin atividades" on public.atividades;
create policy "escrita admin atividades" on public.atividades
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- ---- STORAGE "midia" (bucket público): leitura pública continua,
--       mas upload / alteração / exclusão só de admin ----
drop policy if exists "midia upload admin" on storage.objects;
create policy "midia upload admin" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'midia' and public.eh_admin());

drop policy if exists "midia update admin" on storage.objects;
create policy "midia update admin" on storage.objects
  for update to authenticated
  using (bucket_id = 'midia' and public.eh_admin());

drop policy if exists "midia delete admin" on storage.objects;
create policy "midia delete admin" on storage.objects
  for delete to authenticated
  using (bucket_id = 'midia' and public.eh_admin());

-- Fim.
