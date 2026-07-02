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
