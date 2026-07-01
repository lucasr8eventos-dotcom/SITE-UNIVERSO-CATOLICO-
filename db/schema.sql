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
