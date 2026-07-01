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
