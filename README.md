# Universo Católico Kids

Site com **loja de infoprodutos** (venda de pacotes de PDFs) e **área de
membros**, usando **Supabase** (banco PostgreSQL + login + storage) e
**Mercado Pago** (pagamento automático).

## Páginas

| Caminho | O que é | Quem usa |
|---|---|---|
| `Universo Católico Kids - Site.html` | Site/landing page | Público |
| `loja/index.html` | Vitrine de produtos + checkout (Mercado Pago) | Público |
| `conta/index.html` | Área do cliente: login e acesso aos PDFs comprados | Cliente |
| `admin/index.html` | Admin do conteúdo do site (categorias, livros, atividades) | Você |
| `admin/produtos.html` | Cadastro de produtos + upload dos PDFs | Você |

## Como funciona a venda (automática)

```
Cliente na /loja  →  "Comprar"  →  Mercado Pago (Pix/cartão/boleto)
        │
        ▼ pagamento aprovado (webhook automático)
Acesso liberado no banco  →  cliente faz login na /conta  →  baixa os PDFs
```

- Os **PDFs ficam guardados uma vez só** num bucket privado. 100 compradores
  usam o mesmo arquivo — o armazenamento não cresce por cliente.
- O **banco** guarda só os dados dos clientes e quem comprou o quê.
- O **download** só acontece via link temporário (5 min), gerado depois de
  conferir a compra — ninguém repassa link.

## Configuração (resumo)

1. Preencha `config.js` (raiz) com a URL e a chave **anon** do Supabase.
2. Rode `db/schema.sql` e depois `db/02_loja_membros.sql` no Supabase.
3. Publique as Edge Functions e configure o Mercado Pago — passo a passo em
   **`BACKEND.md`**.
4. Cadastre-se como admin (**`BACKEND.md`**, seção 3).

- Guia do admin de conteúdo: `admin/LEIA-ME.md`
- Guia do backend (pagamento + PDFs): `BACKEND.md`

## Pastas

```
config.js              chaves do Supabase (frontend)
db/                    scripts SQL do banco
admin/                 painéis administrativos
loja/  conta/          páginas públicas da loja e área do cliente
supabase/functions/    Edge Functions (pagamento e download seguro)
```
