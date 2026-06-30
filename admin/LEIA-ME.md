# Painel Admin — Universo Católico Kids

Painel para cadastrar **categorias**, **livros** e **atividades** do site, com
banco de dados profissional (**PostgreSQL** via Supabase) e **login de administrador**.

Arquivos:

```
admin/
  index.html     ← o painel administrativo (abra no navegador)
  config.js      ← onde você cola as chaves do Supabase
  LEIA-ME.md     ← este guia
db/
  schema.sql     ← cria as tabelas do banco de dados
```

---

## Como funciona

- **Sem configurar nada**, o painel abre em **Modo demonstração**: você já
  pode testar todas as telas, e os dados ficam salvos só no seu navegador.
- **Configurando o Supabase** (passos abaixo), o painel passa a gravar num
  **banco de dados real**, com **login e senha** — esse é o modo profissional.

---

## Passo a passo — colocar o banco de dados no ar (grátis)

### 1. Criar o projeto no Supabase
1. Acesse <https://supabase.com> e crie uma conta (pode usar o Google).
2. Clique em **New project**, dê um nome (ex.: `universo-catolico`) e defina
   uma senha do banco. Escolha a região mais próxima (ex.: São Paulo).
3. Aguarde alguns minutos até o projeto ficar pronto.

### 2. Criar as tabelas
1. No menu lateral, abra **SQL Editor → New query**.
2. Abra o arquivo `db/schema.sql`, copie **todo** o conteúdo e cole ali.
3. Clique em **Run**. Isso cria as tabelas `categorias`, `livros` e
   `atividades`, a segurança e já carrega o conteúdo inicial do site.

### 3. Pegar as chaves de conexão
1. No menu, abra **Project Settings → API** (ou **Data API**).
2. Copie dois valores:
   - **Project URL** → algo como `https://xxxx.supabase.co`
   - **anon public** (chave pública) → começa com `eyJ...`

### 4. Configurar o painel
Abra `admin/config.js` e preencha:

```js
window.UCK_CONFIG = {
  SUPABASE_URL: "https://xxxx.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOi...sua-chave-anon...",
};
```

> A chave **anon** é pública e pode ficar no arquivo — quem protege os dados
> é o login + as regras de segurança (RLS) já incluídas no `schema.sql`.
> **Nunca** use a chave `service_role` aqui.

### 5. Criar o usuário administrador (login)
1. No Supabase, abra **Authentication → Users → Add user**.
2. Informe um **e-mail** e uma **senha** para você.
   (Em **Authentication → Providers**, deixe **Email** habilitado e, para
   facilitar, desligue *Confirm email* enquanto for só você.)
3. Pronto: é com esse e-mail e senha que você entra no painel.

### 6. Usar
Abra `admin/index.html`. Vai aparecer a tela de **Entrar**. Faça login e
comece a cadastrar. No topo aparece o selo **● Banco de dados** confirmando
que está gravando no Supabase.

---

## O que dá para cadastrar

- **Categorias**: nome, cor, cor de fundo, ordem de exibição.
- **Livros**: título, categoria, descrição, faixa etária, tempo de leitura,
  preço, preço antigo, desconto, avaliação, imagem da capa (ou cores), e
  link de compra.
- **Atividades**: título, tipo (Colorir, Cruzadinha, Jogo…), faixa etária,
  cores e um PDF para imprimir.

Imagens de capa e PDFs são enviados para o **Storage** do Supabase (bucket
`midia`, criado pelo `schema.sql`).

---

## Conectar o site público ao banco

O site lê os mesmos dados com a chave **anon** (somente leitura é liberada
publicamente). Exemplo de consulta no site:

```js
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const { data: livros } = await sb.from('vw_livros').select('*').eq('ativo', true);
const { data: categorias } = await sb.from('categorias').select('*').eq('ativo', true).order('ordem');
```

A view `vw_livros` já traz cada livro com o nome e a cor da categoria.

---

## Hospedagem

Os arquivos do admin são estáticos (HTML/JS), então funcionam em qualquer
hospedagem: Vercel, Netlify, GitHub Pages, ou hospedagem compartilhada.
O banco fica no Supabase (na nuvem), então não há servidor para manter.

## Backup

O botão **⬇ Exportar** baixa um arquivo `.json` com todo o conteúdo atual —
guarde de tempos em tempos como cópia de segurança.
