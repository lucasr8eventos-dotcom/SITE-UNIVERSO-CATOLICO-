# 🚀 Comece Aqui — Guia completo (Supabase + Mercado Pago)

Este guia leva você **do zero até vender de verdade**, no seu ritmo.
Você já tem conta no Mercado Pago — ótimo. Vamos configurar o banco de dados
(Supabase), plugar o Mercado Pago e testar.

> Tempo estimado: ~30–40 min na primeira vez.
> Não precisa saber programar — é só seguir e copiar/colar.

---

## Visão geral (o que vamos fazer)

1. Criar o banco de dados no **Supabase** (grátis)
2. Rodar os arquivos SQL (criam as tabelas)
3. Pegar as chaves e colar no `config.js`
4. Criar o seu **login de admin**
5. Pegar o **Access Token** do Mercado Pago
6. Instalar a **Supabase CLI** e publicar as funções (a automação do pagamento)
7. **Testar** com cartão de teste
8. Ir para **produção** e vender

---

## PARTE 1 — Banco de dados (Supabase)

### 1.1 Criar o projeto
1. Acesse <https://supabase.com> e faça login (pode usar o Google).
2. Clique em **New project**.
3. Dê um nome (ex.: `universo-catolico`), crie uma **senha do banco** (guarde-a)
   e escolha a região **São Paulo (South America)**.
4. Aguarde ~2 minutos até o projeto ficar pronto.

### 1.2 Criar as tabelas (rodar o SQL)
No menu lateral do Supabase, abra **SQL Editor → New query**.

**Jeito fácil (recomendado):** abra **`db/INSTALAR-TUDO.sql`**, copie **tudo**,
cole no editor e clique em **Run**. Esse arquivo já junta os 9 passos na ordem
certa e cria tabelas, segurança e os buckets de arquivos — tudo de uma vez.

> Se aparecer algum aviso amarelo (NOTICE), tudo bem — é normal. Só não pode dar
> erro vermelho. É seguro rodar de novo se precisar.

<details><summary>Prefere rodar um de cada vez? (opcional)</summary>

Rode nesta ordem (abra o arquivo, copie tudo, cole e **Run**, um por vez):

1. `db/schema.sql`
2. `db/02_loja_membros.sql`
3. `db/03_tipos_produto.sql`
4. `db/04_frete_envio.sql`
5. `db/05_fix_acesso_produto.sql`
6. `db/05_seguranca_admin.sql`
7. `db/06_conteudo_site.sql`
8. `db/06_sacola.sql`
9. `db/07_fix_seguranca_rls.sql`
</details>

### 1.3 Pegar as chaves do projeto
No menu, abra **Project Settings → API** e copie:
- **Project URL** → algo como `https://xxxx.supabase.co`
- **anon public** (chave pública) → começa com `eyJ...`
- **service_role** (chave secreta) → começa com `eyJ...` — **guarde, não coloque no site!**

---

## PARTE 2 — Configurar o site (`config.js`)

Abra o arquivo **`config.js`** (na raiz do projeto) e preencha com o que copiou:

```js
window.UCK_CONFIG = {
  SUPABASE_URL: "https://xxxx.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOi...sua-chave-anon...",
  GA_MEASUREMENT_ID: "",  // opcional — Google Analytics 4 (ex.: "G-ABC123XYZ")
};
```

> **Google Analytics (opcional, recomendado):** crie uma propriedade GA4 em
> <https://analytics.google.com>, copie o "ID da métrica" (começa com `G-`) e
> cole em `GA_MEASUREMENT_ID`. Pronto — todas as páginas passam a medir visitas.

> Só a chave **anon** entra aqui. A **service_role** é secreta e só vai no
> servidor (Parte 5). Salve o arquivo.

---

## PARTE 3 — Criar o seu login de admin

1. No Supabase: **Authentication → Users → Add user**. Coloque seu **e-mail** e
   uma **senha**. Copie o **User UID** que aparece.
2. Em **Authentication → Providers → Email**, desligue **"Confirm email"**
   (deixa a compra mais fluida; você liga depois se quiser).
3. Vá em **SQL Editor** e rode (troque pelo seu UID):
   ```sql
   insert into public.administradores (user_id) values ('COLE_O_UID_AQUI');
   ```

Pronto: é com esse e-mail e senha que você entra em `admin/`.

---

## PARTE 4 — Access Token do Mercado Pago

1. Acesse **[Suas integrações](https://www.mercadopago.com/developers/panel/app)**.
2. Clique em **Criar aplicação**. Dê um nome (ex.: `Universo Católico`) e escolha
   **Pagamentos online → Checkout Pro** (é o que o site usa).
3. Entre na aplicação → **Credenciais**. Você verá dois modos:
   - **Credenciais de teste** → **Access Token** começa com `TEST-...`
   - **Credenciais de produção** → **Access Token** começa com `APP_USR-...`
4. **Comece pelo de TESTE.** Copie o **Access Token de teste**.

> Para o nosso site, você só precisa do **Access Token**. Não precisa de Public Key.

---

## PARTE 5 — Publicar a automação (Supabase CLI)

Aqui a gente publica as **Edge Functions** (o "motor" que fala com o Mercado Pago
e libera o acesso sozinho). Faça no computador, dentro da pasta do projeto.

### 5.1 Instalar a CLI
```bash
npm install -g supabase
```
(precisa ter o Node.js instalado: <https://nodejs.org>)

### 5.2 Conectar ao seu projeto
```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF
```
> O `SEU_PROJECT_REF` é o código que aparece na URL do painel do Supabase
> (`https://supabase.com/dashboard/project/SEU_PROJECT_REF`).

### 5.3 Guardar os segredos (nunca vão para o site)
```bash
supabase secrets set MP_ACCESS_TOKEN="TEST-xxxxxxxx..."     # Access Token de TESTE do Mercado Pago
supabase secrets set SERVICE_ROLE_KEY="eyJ...service_role"  # chave service_role (Parte 1.3)
supabase secrets set SITE_URL="https://seusite.com.br"      # endereço do site (opcional agora)
```

### 5.4 Publicar as funções
```bash
supabase functions deploy criar-pagamento --no-verify-jwt
supabase functions deploy webhook-mercadopago --no-verify-jwt
supabase functions deploy baixar-arquivo --no-verify-jwt
supabase functions deploy admin-clientes --no-verify-jwt
```

> Pronto! A automação está no ar. O `notification_url` (webhook) é enviado
> automaticamente em cada compra — você **não precisa** configurar webhook no
> painel do Mercado Pago.

---

## PARTE 6 — Testar (sem dinheiro real)

1. Abra o site → **Loja** → cadastre um produto de teste no `admin/produtos.html`
   (marque como **ativo** e coloque um preço, ex.: R$ 1,00).
2. Na Loja, clique em **Comprar** e vá até o checkout do Mercado Pago.
3. Pague com um **cartão de teste** do Mercado Pago:
   <https://www.mercadopago.com.br/developers/pt/docs/checkout-pro/additional-content/test-cards>
   (ex.: aprovado — nome do titular **APRO**; use um CPF de teste como `12345678909`).
4. Confira o resultado:
   - No Supabase, a tabela **pedidos** deve mostrar `status = aprovado`.
   - A tabela **acessos** deve ganhar uma linha com o e-mail da compra.
   - No admin **Vendas & Clientes**, a venda aparece.
5. Vá em **`conta/`**, crie a conta com **o mesmo e-mail da compra** e veja o
   produto/PDFs liberados. 🎉

---

## PARTE 7 — Ir para produção (vender de verdade)

Quando os testes estiverem ok:
1. Volte no Mercado Pago → **Credenciais de produção** → copie o **Access Token
   de produção** (`APP_USR-...`).
2. Troque o segredo no Supabase:
   ```bash
   supabase secrets set MP_ACCESS_TOKEN="APP_USR-xxxxxxxx..."
   ```
3. (Não precisa republicar as funções — elas leem o novo segredo.)

A partir daí, as compras são **reais** e caem na sua conta do Mercado Pago.

---

## Checklist final ✅

- [ ] Banco criado no Supabase (`db/INSTALAR-TUDO.sql`)
- [ ] `config.js` preenchido (URL + anon)
- [ ] Admin criado (usuário + linha em `administradores`)
- [ ] `MP_ACCESS_TOKEN`, `SERVICE_ROLE_KEY` e `SITE_URL` definidos no Supabase
- [ ] 4 funções publicadas
- [ ] Compra de teste aprovada e acesso liberado
- [ ] Trocado para o Access Token de produção

---

## Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| Botão "Comprar" dá erro | `MP_ACCESS_TOKEN` errado/ausente | Confira o segredo no Supabase e republique |
| "Área em configuração" na loja | `config.js` vazio | Preencha URL + anon |
| Cliente não vê o produto após pagar | usou e-mail diferente da compra | Deve usar o **mesmo e-mail** do checkout |
| Login do admin diz "não é admin" | faltou a linha em `administradores` | Rode o insert da Parte 3.3 |
| Pediu confirmação de e-mail | "Confirm email" ligado | Desligue em Authentication → Providers |

---

Precisa de ajuda em qualquer passo? Me chame que eu te ajudo a destravar.
O guia técnico mais detalhado está em **`BACKEND.md`**.
