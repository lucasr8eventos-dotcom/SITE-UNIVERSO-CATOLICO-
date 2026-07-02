# Backend — Loja de infoprodutos (Supabase + Mercado Pago)

Este guia coloca no ar a venda dos PDFs com **pagamento automático** e
**área de membros**. Visão geral:

```
Cliente compra  →  Mercado Pago  →  (webhook) libera acesso no banco
                                        ↓
Cliente faz login na Área do Cliente  →  vê os PDFs que comprou
                                        ↓
Clica no PDF  →  Edge Function confere a compra  →  link temporário (5 min)
```

- **Banco de dados** guarda clientes, produtos e quem comprou o quê.
- **Storage privado** guarda os ~300 PDFs **uma única vez** (não duplica por cliente).
- **Edge Functions** fazem a automação e a segurança.

---

## 1. Pré-requisitos

- Conta no **Supabase** (<https://supabase.com>).
- Conta no **Mercado Pago** e as credenciais de desenvolvedor
  (<https://www.mercadopago.com.br/developers>) → **Suas integrações → Credenciais**:
  - `Access Token` (produção) — é o segredo do servidor.
- **Supabase CLI** instalado: <https://supabase.com/docs/guides/cli>
  (`npm i -g supabase` ou pelo instalador do site).

## 2. Criar as tabelas

No painel do Supabase → **SQL Editor**, rode **na ordem**:

1. `db/schema.sql`           (conteúdo do site: categorias, livros, atividades)
2. `db/02_loja_membros.sql`  (loja, membros, produtos, PDFs, pedidos, acessos)
3. `db/03_tipos_produto.sql` (tipos de produto: infoproduto/físico/externo)
4. `db/04_frete_envio.sql`   (frete e controle de envio dos pedidos físicos)
5. `db/05_fix_acesso_produto.sql` (comprador vê produto mesmo se desativado)
6. `db/05_seguranca_admin.sql` (corrige RLS: escrita de conteúdo só para admin)
7. `db/06_conteudo_site.sql` (documentários e blog/artigos)
8. `db/06_sacola.sql`        (sacola: vários produtos em um pagamento só)
9. `db/07_fix_seguranca_rls.sql` (correções de segurança de RLS/Storage + vínculo por e-mail confirmado)

Isso cria inclusive o bucket **privado** `produtos-pdf` para os PDFs.

## 3. Definir o primeiro admin

1. Supabase → **Authentication → Users → Add user**: crie seu usuário
   (e-mail + senha). Copie o **User UID**.
2. Supabase → **SQL Editor**:

   ```sql
   insert into public.administradores (user_id) values ('COLE_O_UID_AQUI');
   ```

Esse usuário passa a poder gerenciar produtos e subir PDFs pelo admin.

## 4. Publicar as Edge Functions

No terminal, dentro da pasta do projeto:

```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF     # aparece na URL do painel

# Segredos usados pelas funções (NUNCA vão para o frontend):
supabase secrets set MP_ACCESS_TOKEN="APP_USR-xxxxxxxx"      # Access Token do Mercado Pago
supabase secrets set SERVICE_ROLE_KEY="eyJ...service_role"   # Project Settings → API
supabase secrets set SITE_URL="https://seudominio.com.br"    # endereço do site publicado

# E-mail automático de acesso (opcional, mas recomendado). Sem estes, o
# acesso é liberado normalmente — só não sai o e-mail pós-compra.
supabase secrets set RESEND_API_KEY="re_xxxxxxxx"                    # https://resend.com → API Keys
supabase secrets set EMAIL_FROM="Universo Católico <acesso@seudominio.com>"  # remetente verificado no Resend

# Publicar as funções:
supabase functions deploy criar-pagamento --no-verify-jwt
supabase functions deploy baixar-arquivo --no-verify-jwt
supabase functions deploy webhook-mercadopago --no-verify-jwt
supabase functions deploy admin-clientes --no-verify-jwt
```

> O `SITE_URL` é **opcional** (o checkout funciona sem ele), mas defina-o
> para o cliente ser redirecionado de volta ao site após pagar.

> `SUPABASE_URL` e `SUPABASE_ANON_KEY` já existem por padrão no ambiente das
> funções — não precisa defini-los.

As funções ficam disponíveis em:

```
https://SEU_REF.supabase.co/functions/v1/criar-pagamento
https://SEU_REF.supabase.co/functions/v1/webhook-mercadopago
https://SEU_REF.supabase.co/functions/v1/baixar-arquivo
```

## 5. Configurar o webhook no Mercado Pago

O `notification_url` já é enviado automaticamente em cada compra, então
normalmente **não precisa** configurar nada no painel do MP. Se quiser
registrar mesmo assim: **Suas integrações → Webhooks**, evento
**Pagamentos**, URL:

```
https://SEU_REF.supabase.co/functions/v1/webhook-mercadopago
```

## 6. Testar (ambiente de teste do Mercado Pago)

1. Use o **Access Token de TESTE** em `MP_ACCESS_TOKEN` durante os testes.
2. No checkout, use os **cartões de teste** do MP
   (<https://www.mercadopago.com.br/developers/pt/docs/checkout-pro/additional-content/test-cards>).
3. Ao aprovar um pagamento de teste, confira no banco:
   - `pedidos.status` vira `aprovado`;
   - surge uma linha em `acessos` com o e-mail do comprador.
4. Faça login na Área do Cliente com esse e-mail e baixe um PDF.

Quando estiver tudo certo, troque para o **Access Token de produção**.

---

## Variáveis de ambiente (resumo)

| Segredo (Supabase Functions) | Onde pegar |
|---|---|
| `MP_ACCESS_TOKEN`  | Mercado Pago → Credenciais (teste ou produção) |
| `SERVICE_ROLE_KEY` | Supabase → Project Settings → API → `service_role` |
| `SITE_URL`         | endereço público do site |
| `RESEND_API_KEY`   | *(opcional)* Resend → API Keys — para o e-mail automático de acesso |
| `EMAIL_FROM`       | *(opcional)* remetente verificado no Resend (ex.: `Nome <acesso@seudominio.com>`) |

| Config do frontend (`config.js` na raiz) | Onde pegar |
|---|---|
| `SUPABASE_URL`      | Supabase → Project Settings → API |
| `SUPABASE_ANON_KEY` | Supabase → Project Settings → API (`anon public`) |

> A `service_role` é **secreta** e só entra nas Edge Functions. No frontend
> use **apenas** a `anon`.

## Custo / "memória"

- **Storage**: os 300 PDFs ocupam o tamanho deles **uma vez só** (ex.: 300 ×
  2 MB ≈ 600 MB), não importa quantas pessoas comprem.
- **Banco**: cada cliente/compra é uma linha de texto (quilobytes).
- **Banda** (download) é o que cresce com o volume de vendas. Se ficar alto,
  dá para migrar o bucket para um storage sem cobrança de saída (ex.:
  Cloudflare R2) mantendo a mesma lógica de link temporário.
