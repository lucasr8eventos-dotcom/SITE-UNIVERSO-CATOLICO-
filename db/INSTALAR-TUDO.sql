-- =====================================================================
--  UNIVERSO CATÓLICO KIDS — INSTALAÇÃO COMPLETA DO BANCO (Supabase)
--  ---------------------------------------------------------------------
--  Rode ESTE arquivo UMA vez no Supabase (SQL Editor → New query →
--  cole tudo → Run). Ele junta, na ordem certa, os 9 arquivos de db/.
--
--  É seguro rodar mais de uma vez (usa "if exists / or replace").
--  Avisos amarelos (NOTICE) são normais; só não pode dar erro vermelho.
--  Testado num Postgres real: roda limpo do zero.
-- =====================================================================


-- ═══════════════════════════════════════════════════════════════════
--  db/schema.sql
-- ═══════════════════════════════════════════════════════════════════
-- =====================================================================
--  UNIVERSO CATÓLICO KIDS — Banco de dados (PostgreSQL / Supabase)
--  Tabelas: categorias, livros, atividades
--  Inclui: segurança (RLS), índices, gatilhos e dados iniciais (seed).
--
--  Como usar no Supabase:
--    1. Crie um projeto em https://supabase.com
--    2. Vá em "SQL Editor" -> "New query"
--    3. Cole TODO este arquivo e clique em "Run"
--  Funciona também em qualquer PostgreSQL 13+ (remova as partes "auth"/RLS
--  se for usar um backend próprio).
-- =====================================================================

create extension if not exists "pgcrypto";   -- para gen_random_uuid()

-- ---------------------------------------------------------------------
--  Função utilitária: atualiza "atualizado_em" em cada UPDATE
-- ---------------------------------------------------------------------
create or replace function public.set_atualizado_em()
returns trigger language plpgsql as $$
begin
  new.atualizado_em = now();
  return new;
end; $$;

-- =====================================================================
--  CATEGORIAS
-- =====================================================================
create table if not exists public.categorias (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null,
  cor           text not null default '#1f57c3',   -- cor principal do selo
  cor_fundo     text not null default '#e7efff',   -- tom suave de fundo
  ordem         int  not null default 0,           -- ordem de exibição no site
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

drop trigger if exists trg_categorias_upd on public.categorias;
create trigger trg_categorias_upd before update on public.categorias
  for each row execute function public.set_atualizado_em();

-- =====================================================================
--  LIVROS
-- =====================================================================
create table if not exists public.livros (
  id             uuid primary key default gen_random_uuid(),
  titulo         text not null,
  categoria_id   uuid references public.categorias(id) on delete set null,
  descricao      text,
  faixa_etaria   text,                    -- ex.: "3-6 anos"
  tempo_leitura  text,                    -- ex.: "10 min/dia"
  preco          numeric(10,2),           -- ex.: 49.90
  preco_antigo   numeric(10,2),           -- ex.: 69.90
  desconto       text,                    -- ex.: "-28%"
  avaliacao      numeric(2,1),            -- ex.: 4.9
  capa_cor1      text default '#2f8fd6',  -- topo do gradiente da capa
  capa_cor2      text default '#1f57c3',  -- base do gradiente da capa
  capa_url       text,                    -- imagem da capa (Storage)
  link_compra    text,                    -- link externo (Amazon etc.)
  destaque       boolean not null default false,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

create index if not exists idx_livros_categoria on public.livros(categoria_id);

drop trigger if exists trg_livros_upd on public.livros;
create trigger trg_livros_upd before update on public.livros
  for each row execute function public.set_atualizado_em();

-- =====================================================================
--  ATIVIDADES
-- =====================================================================
create table if not exists public.atividades (
  id             uuid primary key default gen_random_uuid(),
  titulo         text not null,
  tipo           text,                    -- Colorir, Cruzadinha, Jogo...
  faixa_etaria   text,                    -- ex.: "3 anos"
  cor            text not null default '#e8533f',
  cor_fundo      text not null default '#fde9e5',
  arquivo_url    text,                    -- PDF para imprimir (Storage)
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

drop trigger if exists trg_atividades_upd on public.atividades;
create trigger trg_atividades_upd before update on public.atividades
  for each row execute function public.set_atualizado_em();

-- =====================================================================
--  SEGURANÇA (Row Level Security)
--  Regra: qualquer visitante PODE LER (o site mostra o conteúdo),
--         apenas usuários AUTENTICADOS (admin logado) podem escrever.
-- =====================================================================
alter table public.categorias enable row level security;
alter table public.livros     enable row level security;
alter table public.atividades enable row level security;

-- Leitura pública
drop policy if exists "leitura publica categorias" on public.categorias;
create policy "leitura publica categorias" on public.categorias for select using (true);
drop policy if exists "leitura publica livros" on public.livros;
create policy "leitura publica livros" on public.livros for select using (true);
drop policy if exists "leitura publica atividades" on public.atividades;
create policy "leitura publica atividades" on public.atividades for select using (true);

-- Escrita apenas autenticada (insert/update/delete)
drop policy if exists "escrita admin categorias" on public.categorias;
create policy "escrita admin categorias" on public.categorias
  for all to authenticated using (true) with check (true);
drop policy if exists "escrita admin livros" on public.livros;
create policy "escrita admin livros" on public.livros
  for all to authenticated using (true) with check (true);
drop policy if exists "escrita admin atividades" on public.atividades;
create policy "escrita admin atividades" on public.atividades
  for all to authenticated using (true) with check (true);

-- =====================================================================
--  STORAGE (imagens de capa e PDFs de atividades)
--  Cria um bucket público "midia" para arquivos enviados pelo admin.
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('midia', 'midia', true)
on conflict (id) do nothing;

drop policy if exists "midia leitura publica" on storage.objects;
create policy "midia leitura publica" on storage.objects
  for select using (bucket_id = 'midia');
drop policy if exists "midia upload admin" on storage.objects;
create policy "midia upload admin" on storage.objects
  for insert to authenticated with check (bucket_id = 'midia');
drop policy if exists "midia update admin" on storage.objects;
create policy "midia update admin" on storage.objects
  for update to authenticated using (bucket_id = 'midia');
drop policy if exists "midia delete admin" on storage.objects;
create policy "midia delete admin" on storage.objects
  for delete to authenticated using (bucket_id = 'midia');

-- =====================================================================
--  DADOS INICIAIS (seed) — só insere se a tabela estiver vazia
-- =====================================================================
insert into public.categorias (nome, cor, cor_fundo, ordem)
select * from (values
  ('Histórias da Bíblia', '#1f57c3', '#e7efff', 1),
  ('Vida de Jesus',       '#e8533f', '#fde9e5', 2),
  ('Nossa Senhora',       '#2f8fd6', '#e6f3fc', 3),
  ('Santos',              '#f5b21a', '#fff3d6', 4),
  ('Virtudes',            '#2fa15a', '#e4f5ea', 5),
  ('Sacramentos',         '#7c4dd6', '#efe7fb', 6),
  ('Primeira Comunhão',   '#d6a015', '#fbf1d2', 7),
  ('Catequese',           '#1f57c3', '#e7efff', 8),
  ('Parábolas',           '#e8533f', '#fde9e5', 9),
  ('Orações',             '#2fa15a', '#e4f5ea', 10)
) as v(nome, cor, cor_fundo, ordem)
where not exists (select 1 from public.categorias);

insert into public.livros (titulo, categoria_id, descricao, faixa_etaria, tempo_leitura, preco, preco_antigo, desconto, avaliacao, capa_cor1, capa_cor2, destaque)
select v.titulo, c.id, v.descricao, v.faixa_etaria, v.tempo_leitura, v.preco, v.preco_antigo, v.desconto, v.avaliacao, v.capa_cor1, v.capa_cor2, true
from (values
  ('Minha Primeira Bíblia', 'Histórias da Bíblia', 'As mais belas histórias bíblicas, ilustradas para os pequenos.', '3-6 anos', '10 min/dia', 49.90, 69.90, '-28%', 4.9, '#2f8fd6', '#1f57c3'),
  ('A Vida de Jesus', 'Vida de Jesus', 'Do nascimento à ressurreição, contada com ternura para crianças.', '5-9 anos', '15 min', 59.90, 79.90, '-25%', 4.8, '#f5803a', '#e8533f'),
  ('Maria, Mãe de Todos', 'Nossa Senhora', 'A história de Nossa Senhora e seu amor por cada família.', '4-8 anos', '12 min', 44.90, 59.90, '-25%', 5.0, '#4aa8e0', '#2f8fd6'),
  ('Pequenos Grandes Santos', 'Santos', 'Conheça os santos que foram crianças corajosas na fé.', '6-10 anos', '20 min', 64.90, 84.90, '-24%', 4.9, '#f5b21a', '#d6a015')
) as v(titulo, categoria, descricao, faixa_etaria, tempo_leitura, preco, preco_antigo, desconto, avaliacao, capa_cor1, capa_cor2)
left join public.categorias c on c.nome = v.categoria
where not exists (select 1 from public.livros);

insert into public.atividades (titulo, tipo, faixa_etaria, cor, cor_fundo)
select * from (values
  ('Jesus ama as crianças',    'Colorir',    '3 anos', '#e8533f', '#fde9e5'),
  ('Cruzadinha dos Apóstolos', 'Cruzadinha', '7 anos', '#1f57c3', '#e7efff'),
  ('Memória dos Santos',       'Jogo',       '5 anos', '#2fa15a', '#e4f5ea'),
  ('Labirinto da Arca de Noé', 'Labirinto',  '4 anos', '#7c4dd6', '#efe7fb')
) as v(titulo, tipo, faixa_etaria, cor, cor_fundo)
where not exists (select 1 from public.atividades);

-- =====================================================================
--  VIEW de conveniência: livros já com o nome da categoria (para o site)
-- =====================================================================
create or replace view public.vw_livros as
select l.*, c.nome as categoria_nome, c.cor as categoria_cor
from public.livros l
left join public.categorias c on c.id = l.categoria_id;

-- Fim.


-- ═══════════════════════════════════════════════════════════════════
--  db/02_loja_membros.sql
-- ═══════════════════════════════════════════════════════════════════
-- =====================================================================
--  UNIVERSO CATÓLICO KIDS — LOJA DE INFOPRODUTOS + ÁREA DE MEMBROS
--  (rodar DEPOIS do db/schema.sql)
--
--  Modelo:
--    produtos          -> cada infoproduto à venda (vários produtos)
--    modulos           -> "pastas" dentro de um produto (organiza os PDFs)
--    arquivos          -> os PDFs (guardados 1x no Storage privado)
--    administradores   -> quem pode usar o painel admin
--    pedidos           -> cada tentativa de compra (status do pagamento)
--    acessos           -> liberação: quem pode acessar qual produto
--
--  Os PDFs ficam num bucket PRIVADO. O download só acontece via Edge
--  Function, que confere a compra e gera um link temporário.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
--  Quem é admin? (usado nas regras de segurança)
-- ---------------------------------------------------------------------
create table if not exists public.administradores (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now()
);
alter table public.administradores enable row level security;
-- cada usuário pode verificar se ele mesmo é admin
drop policy if exists "admin ve a si mesmo" on public.administradores;
create policy "admin ve a si mesmo" on public.administradores
  for select to authenticated using (user_id = auth.uid());
-- (inserir o 1º admin é feito manualmente — veja o LEIA-ME)

create or replace function public.eh_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.administradores where user_id = auth.uid());
$$;

-- e-mail do usuário logado (para casar acessos comprados antes de criar conta)
create or replace function public.email_logado()
returns text language sql stable as $$
  select nullif(lower(auth.jwt() ->> 'email'), '');
$$;

-- ---------------------------------------------------------------------
--  PRODUTOS
-- ---------------------------------------------------------------------
create table if not exists public.produtos (
  id            uuid primary key default gen_random_uuid(),
  slug          text unique not null,
  nome          text not null,
  descricao     text,
  preco         numeric(10,2) not null default 0,
  preco_antigo  numeric(10,2),
  capa_url      text,
  capa_cor1     text default '#2f8fd6',
  capa_cor2     text default '#1f57c3',
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
drop trigger if exists trg_produtos_upd on public.produtos;
create trigger trg_produtos_upd before update on public.produtos
  for each row execute function public.set_atualizado_em();

-- ---------------------------------------------------------------------
--  MÓDULOS (pastas do produto)
-- ---------------------------------------------------------------------
create table if not exists public.modulos (
  id         uuid primary key default gen_random_uuid(),
  produto_id uuid not null references public.produtos(id) on delete cascade,
  nome       text not null,
  ordem      int  not null default 0,
  criado_em  timestamptz not null default now()
);
create index if not exists idx_modulos_produto on public.modulos(produto_id);

-- ---------------------------------------------------------------------
--  ARQUIVOS (os PDFs)
-- ---------------------------------------------------------------------
create table if not exists public.arquivos (
  id            uuid primary key default gen_random_uuid(),
  produto_id    uuid not null references public.produtos(id) on delete cascade,
  modulo_id     uuid references public.modulos(id) on delete set null,
  titulo        text not null,
  caminho       text not null,          -- caminho dentro do bucket privado
  tamanho_bytes bigint,
  ordem         int not null default 0,
  criado_em     timestamptz not null default now()
);
create index if not exists idx_arquivos_produto on public.arquivos(produto_id);
create index if not exists idx_arquivos_modulo  on public.arquivos(modulo_id);

-- ---------------------------------------------------------------------
--  PEDIDOS (uma linha por tentativa de compra)
-- ---------------------------------------------------------------------
create table if not exists public.pedidos (
  id                uuid primary key default gen_random_uuid(),
  produto_id        uuid references public.produtos(id) on delete set null,
  email             text not null,          -- e-mail do comprador
  nome              text,
  valor             numeric(10,2),
  status            text not null default 'pendente',  -- pendente|aprovado|recusado|estornado
  mp_preference_id  text,
  mp_payment_id     text,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);
create index if not exists idx_pedidos_email on public.pedidos(lower(email));
create index if not exists idx_pedidos_mp_pref on public.pedidos(mp_preference_id);
drop trigger if exists trg_pedidos_upd on public.pedidos;
create trigger trg_pedidos_upd before update on public.pedidos
  for each row execute function public.set_atualizado_em();

-- ---------------------------------------------------------------------
--  ACESSOS (entitlements) — quem pode acessar o produto
--  A chave é o e-mail: a pessoa compra e o acesso é liberado pelo e-mail;
--  quando ela cria/loga a conta com esse mesmo e-mail, já enxerga tudo.
-- ---------------------------------------------------------------------
create table if not exists public.acessos (
  id         uuid primary key default gen_random_uuid(),
  email      text not null,
  produto_id uuid not null references public.produtos(id) on delete cascade,
  user_id    uuid references auth.users(id) on delete set null,
  pedido_id  uuid references public.pedidos(id) on delete set null,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now(),
  unique (email, produto_id)
);
create index if not exists idx_acessos_email on public.acessos(lower(email));
create index if not exists idx_acessos_user on public.acessos(user_id);

-- ---------------------------------------------------------------------
--  Helper: o usuário logado tem acesso a este produto?
-- ---------------------------------------------------------------------
create or replace function public.tem_acesso(p_produto uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.eh_admin() or exists (
    select 1 from public.acessos a
    where a.produto_id = p_produto and a.ativo
      and (a.user_id = auth.uid() or lower(a.email) = public.email_logado())
  );
$$;

-- =====================================================================
--  SEGURANÇA (RLS)
-- =====================================================================
alter table public.produtos enable row level security;
alter table public.modulos  enable row level security;
alter table public.arquivos enable row level security;
alter table public.pedidos  enable row level security;
alter table public.acessos  enable row level security;

-- PRODUTOS: catálogo é público (só os ativos); admin gerencia tudo
drop policy if exists "produtos leitura publica" on public.produtos;
create policy "produtos leitura publica" on public.produtos
  for select using (ativo = true or public.eh_admin());
drop policy if exists "produtos admin escreve" on public.produtos;
create policy "produtos admin escreve" on public.produtos
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- MÓDULOS: vê quem comprou o produto (ou admin); admin gerencia
drop policy if exists "modulos leitura" on public.modulos;
create policy "modulos leitura" on public.modulos
  for select to authenticated using (public.tem_acesso(produto_id));
drop policy if exists "modulos admin escreve" on public.modulos;
create policy "modulos admin escreve" on public.modulos
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- ARQUIVOS: metadados visíveis só para quem comprou (o download é via Edge Function)
drop policy if exists "arquivos leitura" on public.arquivos;
create policy "arquivos leitura" on public.arquivos
  for select to authenticated using (public.tem_acesso(produto_id));
drop policy if exists "arquivos admin escreve" on public.arquivos;
create policy "arquivos admin escreve" on public.arquivos
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- PEDIDOS: o cliente vê os próprios; criação/atualização é via Edge Function (service role)
drop policy if exists "pedidos proprio" on public.pedidos;
create policy "pedidos proprio" on public.pedidos
  for select to authenticated using (public.eh_admin() or lower(email) = public.email_logado());

-- ACESSOS: o cliente vê os próprios; liberação é via Edge Function (service role)
drop policy if exists "acessos proprio" on public.acessos;
create policy "acessos proprio" on public.acessos
  for select to authenticated using (public.eh_admin() or lower(email) = public.email_logado() or user_id = auth.uid());

-- =====================================================================
--  STORAGE — bucket PRIVADO para os PDFs vendidos
--  (não tem política pública: só a Edge Function, com service role,
--   gera links temporários de download)
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('produtos-pdf', 'produtos-pdf', false)
on conflict (id) do nothing;

-- admin pode subir/editar/excluir PDFs pelo painel
drop policy if exists "pdf admin gerencia" on storage.objects;
create policy "pdf admin gerencia" on storage.objects
  for all to authenticated
  using (bucket_id = 'produtos-pdf' and public.eh_admin())
  with check (bucket_id = 'produtos-pdf' and public.eh_admin());

-- =====================================================================
--  Quando um usuário novo confirma a conta, vincula os acessos
--  que foram comprados com aquele e-mail (preenche user_id).
-- =====================================================================
create or replace function public.vincular_acessos_novo_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.acessos set user_id = new.id
  where user_id is null and lower(email) = lower(new.email);
  update public.pedidos set atualizado_em = now()  -- noop seguro
  where false;
  return new;
end; $$;

drop trigger if exists trg_vincular_acessos on auth.users;
create trigger trg_vincular_acessos after insert on auth.users
  for each row execute function public.vincular_acessos_novo_usuario();

-- =====================================================================
--  DADOS DE EXEMPLO (só se não houver produtos)
-- =====================================================================
insert into public.produtos (slug, nome, descricao, preco, preco_antigo)
select 'colecao-biblia-kids', 'Coleção Bíblia Kids — 300 Atividades',
       'Mais de 300 PDFs com histórias, atividades e desenhos para imprimir.',
       97.00, 197.00
where not exists (select 1 from public.produtos);

-- Fim.


-- ═══════════════════════════════════════════════════════════════════
--  db/03_tipos_produto.sql
-- ═══════════════════════════════════════════════════════════════════
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


-- ═══════════════════════════════════════════════════════════════════
--  db/04_frete_envio.sql
-- ═══════════════════════════════════════════════════════════════════
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


-- ═══════════════════════════════════════════════════════════════════
--  db/05_fix_acesso_produto.sql
-- ═══════════════════════════════════════════════════════════════════
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


-- ═══════════════════════════════════════════════════════════════════
--  db/05_seguranca_admin.sql
-- ═══════════════════════════════════════════════════════════════════
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


-- ═══════════════════════════════════════════════════════════════════
--  db/06_conteudo_site.sql
-- ═══════════════════════════════════════════════════════════════════
-- =====================================================================
--  CONTEÚDO DO SITE: Documentários e Blog (artigos)
--  (rodar DEPOIS de db/05_fix_acesso_produto.sql)
--  As "atividades para imprimir" já existem na tabela public.atividades
--  (criada em db/schema.sql).
-- =====================================================================

-- ---------------------------------------------------------------------
--  DOCUMENTÁRIOS
-- ---------------------------------------------------------------------
create table if not exists public.documentarios (
  id            uuid primary key default gen_random_uuid(),
  titulo        text not null,
  tema          text,
  descricao     text,
  duracao       text,                     -- ex.: "48 min"
  faixa         text,                     -- ex.: "Livre", "6+"
  capa_url      text,
  capa_cor1     text default '#2f8fd6',
  capa_cor2     text default '#15418c',
  link_video    text,                     -- link do vídeo (YouTube/Vimeo)
  ordem         int  not null default 0,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------
--  ARTIGOS (Blog)
-- ---------------------------------------------------------------------
create table if not exists public.artigos (
  id             uuid primary key default gen_random_uuid(),
  titulo         text not null,
  resumo         text,
  conteudo       text,                    -- texto completo do artigo
  tag            text,                    -- ex.: "Catequese"
  tag_cor        text default '#1f57c3',
  capa_url       text,
  capa_cor1      text default '#2f8fd6',
  capa_cor2      text default '#1f57c3',
  tempo_leitura  text,                    -- ex.: "5 min de leitura"
  ordem          int not null default 0,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

-- gatilhos de atualizado_em (função set_atualizado_em criada no schema.sql)
drop trigger if exists trg_documentarios_upd on public.documentarios;
create trigger trg_documentarios_upd before update on public.documentarios
  for each row execute function public.set_atualizado_em();
drop trigger if exists trg_artigos_upd on public.artigos;
create trigger trg_artigos_upd before update on public.artigos
  for each row execute function public.set_atualizado_em();

-- ---------------------------------------------------------------------
--  SEGURANÇA: leitura pública, escrita só do admin
-- ---------------------------------------------------------------------
alter table public.documentarios enable row level security;
alter table public.artigos       enable row level security;

drop policy if exists "doc leitura publica" on public.documentarios;
create policy "doc leitura publica" on public.documentarios
  for select using (ativo = true or public.eh_admin());
drop policy if exists "doc admin escreve" on public.documentarios;
create policy "doc admin escreve" on public.documentarios
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists "artigos leitura publica" on public.artigos;
create policy "artigos leitura publica" on public.artigos
  for select using (ativo = true or public.eh_admin());
drop policy if exists "artigos admin escreve" on public.artigos;
create policy "artigos admin escreve" on public.artigos
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

-- ---------------------------------------------------------------------
--  DADOS DE EXEMPLO (só se vazio)
-- ---------------------------------------------------------------------
insert into public.documentarios (titulo, tema, descricao, duracao, faixa, capa_cor1, capa_cor2, ordem)
select * from (values
  ('A Vida de Jesus', 'Vida de Jesus', 'Uma jornada pelos passos de Cristo, narrada para toda a família.', '48 min', 'Livre', '#2f8fd6', '#15418c', 1),
  ('Santos que Mudaram o Mundo', 'Santos', 'Histórias inspiradoras de homens e mulheres de fé.', '35 min', '6+', '#f5b21a', '#d6a015', 2),
  ('Aparições de Nossa Senhora', 'Aparições', 'Fátima, Lourdes e Guadalupe contadas para crianças.', '52 min', 'Livre', '#4aa8e0', '#1f57c3', 3)
) as v(titulo,tema,descricao,duracao,faixa,capa_cor1,capa_cor2,ordem)
where not exists (select 1 from public.documentarios);

insert into public.artigos (titulo, resumo, conteudo, tag, tag_cor, tempo_leitura, capa_cor1, capa_cor2, ordem)
select * from (values
  ('10 histórias bíblicas para a hora de dormir', 'Uma seleção de histórias curtas e cheias de fé para encerrar o dia com paz.', 'Conteúdo do artigo aqui. Edite no painel admin.', 'Catequese', '#1f57c3', '5 min de leitura', '#2f8fd6', '#1f57c3', 1),
  ('A vida de São Francisco para crianças', 'Conheça a história do santo que amava os animais e a simplicidade.', 'Conteúdo do artigo aqui. Edite no painel admin.', 'Santos', '#c98a04', '7 min de leitura', '#f5b21a', '#d6a015', 2),
  ('Como criar o hábito da oração em família', 'Dicas práticas para incluir a oração no dia a dia dos pequenos.', 'Conteúdo do artigo aqui. Edite no painel admin.', 'Família', '#e8533f', '6 min de leitura', '#f5803a', '#e8533f', 3)
) as v(titulo,resumo,conteudo,tag,tag_cor,tempo_leitura,capa_cor1,capa_cor2,ordem)
where not exists (select 1 from public.artigos);

-- Fim.


-- ═══════════════════════════════════════════════════════════════════
--  db/06_sacola.sql
-- ═══════════════════════════════════════════════════════════════════
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


-- ═══════════════════════════════════════════════════════════════════
--  db/07_fix_seguranca_rls.sql
-- ═══════════════════════════════════════════════════════════════════
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

