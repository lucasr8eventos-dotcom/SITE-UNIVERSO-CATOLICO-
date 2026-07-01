// =====================================================================
//  criar-pagamento
//  Recebe do site:
//    { itens: [{ produto_id, quantidade }], email, nome, cpf, telefone,
//      endereco }
//  (também aceita o formato antigo { produto_id, ... } de 1 item só).
//
//  Cria UM pedido com todos os itens da sacola e UMA "preference" no
//  Mercado Pago (um pagamento só). Devolve o link do checkout.
//
//  O preço de cada item vem SEMPRE do banco, nunca do cliente (segurança).
//  A preferência é enviada com o máximo de dados possível (comprador,
//  itens, descrição, referência externa, webhook, statement_descriptor)
//  para elevar a taxa de aprovação e a nota de qualidade da integração.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors, json } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;
const MP_TOKEN = Deno.env.get("MP_ACCESS_TOKEN")!;
const SITE_URL = Deno.env.get("SITE_URL") ?? "";

// Nome que aparece na fatura do cartão do comprador (máx. 22 caracteres,
// só letras/números). Reduz contestações ("não reconheço essa compra").
const STATEMENT_DESCRIPTOR = "UNIVERSOCATOLICO";

// Só dígitos, útil para CPF, CEP e telefone.
const soDigitos = (v: unknown) => String(v ?? "").replace(/\D/g, "");

// Quebra "João da Silva" em { first: "João", last: "da Silva" }.
function separarNome(nome: unknown) {
  const partes = String(nome ?? "").trim().split(/\s+/).filter(Boolean);
  const first = partes.shift() ?? "";
  const last = partes.join(" ");
  return { first, last };
}

// Monta o objeto payer.phone do Mercado Pago a partir de um telefone BR.
function montarTelefone(tel: unknown) {
  const d = soDigitos(tel);
  if (d.length < 10) return null;
  return { area_code: d.slice(0, 2), number: d.slice(2) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erro: "Método inválido" }, 405);

  try {
    const body = await req.json();
    const { email, nome, cpf, telefone, endereco } = body;

    // Aceita a sacola (itens[]) ou o formato antigo de 1 produto.
    const linhasBrutas = Array.isArray(body.itens) && body.itens.length
      ? body.itens
      : (body.produto_id
        ? [{ produto_id: body.produto_id, quantidade: 1 }]
        : []);

    if (!email || !linhasBrutas.length) {
      return json({ erro: "Informe os itens e o e-mail" }, 400);
    }

    // Normaliza quantidades (mín. 1) e remove itens sem id.
    const linhas = linhasBrutas
      .map((l: any) => ({
        produto_id: l.produto_id,
        quantidade: Math.max(1, Number(l.quantidade) || 1),
      }))
      .filter((l: any) => l.produto_id);
    if (!linhas.length) return json({ erro: "Sacola vazia" }, 400);

    const db = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Busca TODOS os produtos da sacola de uma vez (preços do banco).
    const ids = [...new Set(linhas.map((l: any) => l.produto_id))];
    const { data: produtos, error: e1 } = await db
      .from("produtos")
      .select("id, nome, preco, ativo, tipo, frete, descricao, descricao_curta")
      .in("id", ids);
    if (e1 || !produtos || !produtos.length) {
      return json({ erro: "Produtos não encontrados" }, 404);
    }
    const mapa: Record<string, any> = Object.fromEntries(
      produtos.map((p) => [p.id, p]),
    );

    // Valida e monta os itens do Mercado Pago + os itens do pedido.
    const mpItems: Record<string, unknown>[] = [];
    const itensPedido: Record<string, unknown>[] = [];
    let subtotal = 0;
    let frete = 0;
    let temFisico = false;

    for (const l of linhas) {
      const p = mapa[l.produto_id];
      if (!p) return json({ erro: "Produto não encontrado" }, 404);
      if (!p.ativo) return json({ erro: `Produto indisponível: ${p.nome}` }, 400);
      if (p.tipo === "externo") {
        return json({ erro: `Produto vendido em link externo: ${p.nome}` }, 400);
      }
      const qty = l.quantidade;
      const desc = p.descricao_curta || p.descricao || p.nome;
      mpItems.push({
        id: String(p.id),
        title: p.nome,
        description: String(desc).slice(0, 250),
        category_id: p.tipo === "fisico" ? "others" : "virtual_goods",
        quantity: qty,
        currency_id: "BRL",
        unit_price: Number(p.preco),
      });
      itensPedido.push({
        produto_id: p.id,
        nome: p.nome,
        preco: Number(p.preco),
        tipo: p.tipo,
        quantidade: qty,
      });
      subtotal += Number(p.preco) * qty;
      if (p.tipo === "fisico") {
        temFisico = true;
        frete += Number(p.frete || 0) * qty;
      }
    }

    if (temFisico && !endereco) {
      return json({ erro: "Informe o endereço de entrega" }, 400);
    }
    const valorTotal = subtotal + frete;
    if (valorTotal <= 0) return json({ erro: "Valor da sacola inválido" }, 400);

    const emailLimpo = String(email).toLowerCase().trim();
    const nomeCompleto = nome ?? endereco?.nome ?? null;
    const telefoneBruto = telefone ?? endereco?.telefone ?? null;

    // Cria UM pedido com todos os itens (produto_id = 1º item p/ compat.).
    const { data: pedido, error: e2 } = await db
      .from("pedidos")
      .insert({
        produto_id: itensPedido[0].produto_id,
        itens: itensPedido,
        email: emailLimpo,
        nome: nomeCompleto,
        valor: valorTotal,
        status: "pendente",
        endereco: endereco ?? null,
      })
      .select("id")
      .single();
    if (e2 || !pedido) return json({ erro: "Falha ao criar pedido" }, 500);

    // ---- Monta o objeto "payer" o mais completo possível ---------------
    const { first, last } = separarNome(nomeCompleto);
    const payer: Record<string, unknown> = { email: emailLimpo };
    if (first) payer.name = first;
    if (last) payer.surname = last;
    const fone = montarTelefone(telefoneBruto);
    if (fone) payer.phone = fone;
    const cpfLimpo = soDigitos(cpf);
    if (cpfLimpo.length === 11) {
      payer.identification = { type: "CPF", number: cpfLimpo };
    }
    if (temFisico && endereco) {
      payer.address = {
        zip_code: soDigitos(endereco.cep),
        street_name: String(endereco.endereco ?? "").trim(),
        street_number: "",
      };
    }

    // ---- Monta a preference -------------------------------------------
    const webhook = `${SUPABASE_URL}/functions/v1/webhook-mercadopago`;
    const pref: Record<string, unknown> = {
      items: mpItems,
      payer,
      external_reference: pedido.id, // liga o pagamento ao nosso pedido
      notification_url: webhook,
      statement_descriptor: STATEMENT_DESCRIPTOR,
      metadata: { pedido_id: pedido.id },
      // binary_mode fica FALSE de propósito: Pix e boleto ficam "pendentes"
      // até compensar, e binary_mode=true recusaria esses meios.
    };
    if (frete > 0) pref.shipments = { cost: frete, mode: "not_specified" };

    // back_urls/auto_return só entram quando há SITE_URL válido — se enviarmos
    // uma URL relativa, o Mercado Pago RECUSA a preferência. Sem SITE_URL, o
    // checkout funciona igual (só não redireciona sozinho de volta ao site).
    const site = (SITE_URL || "").replace(/\/+$/, "");
    if (/^https?:\/\//i.test(site)) {
      const em = encodeURIComponent(emailLimpo);
      pref.back_urls = {
        success: `${site}/conta/?compra=sucesso&email=${em}`,
        pending: `${site}/conta/?compra=pendente&email=${em}`,
        failure: `${site}/conta/?compra=falha`,
      };
      pref.auto_return = "approved";
    }

    const mp = await fetch("https://api.mercadopago.com/checkout/preferences", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${MP_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(pref),
    });
    const mpData = await mp.json();
    if (!mp.ok) {
      return json({ erro: "Mercado Pago recusou", detalhe: mpData }, 502);
    }

    // Guarda a referência da preference no pedido
    await db.from("pedidos").update({ mp_preference_id: mpData.id }).eq(
      "id",
      pedido.id,
    );

    return json({
      pedido_id: pedido.id,
      preference_id: mpData.id,
      init_point: mpData.init_point, // link do checkout (produção)
      sandbox_init_point: mpData.sandbox_init_point, // link do checkout (teste)
    });
  } catch (err) {
    return json({ erro: String(err?.message ?? err) }, 500);
  }
});
