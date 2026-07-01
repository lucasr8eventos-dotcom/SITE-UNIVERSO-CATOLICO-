// =====================================================================
//  criar-pagamento
//  Recebe { produto_id, email, nome, cpf, telefone, endereco } do site,
//  cria um PEDIDO (pendente) e uma "preference" no Mercado Pago.
//  Devolve o link do checkout.
//
//  A preferência é enviada com o máximo de dados possível (comprador,
//  item, descrição, referência externa, webhook, statement_descriptor).
//  Quanto mais completa, maior a taxa de aprovação e a nota de qualidade
//  da integração no Mercado Pago (checklist oficial).
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
    const { produto_id, email, nome, cpf, telefone, endereco } = await req
      .json();
    if (!produto_id || !email) {
      return json({ erro: "Informe produto_id e email" }, 400);
    }

    const db = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Busca o produto (preço vem do banco, nunca do cliente — segurança)
    const { data: produto, error: e1 } = await db
      .from("produtos")
      .select("id, nome, preco, ativo, tipo, frete, descricao, descricao_curta")
      .eq("id", produto_id)
      .single();
    if (e1 || !produto) return json({ erro: "Produto não encontrado" }, 404);
    if (!produto.ativo) return json({ erro: "Produto indisponível" }, 400);
    if (produto.tipo === "externo") {
      return json({ erro: "Este produto é vendido em link externo" }, 400);
    }
    if (produto.tipo === "fisico" && !endereco) {
      return json({ erro: "Informe o endereço de entrega" }, 400);
    }

    const emailLimpo = String(email).toLowerCase().trim();
    const nomeCompleto = nome ?? endereco?.nome ?? null;
    const telefoneBruto = telefone ?? endereco?.telefone ?? null;
    const frete = produto.tipo === "fisico" ? Number(produto.frete || 0) : 0;
    const valorTotal = Number(produto.preco) + frete;

    // Cria o pedido pendente (valor já com frete, quando houver)
    const { data: pedido, error: e2 } = await db
      .from("pedidos")
      .insert({
        produto_id: produto.id,
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
    if (produto.tipo === "fisico" && endereco) {
      payer.address = {
        zip_code: soDigitos(endereco.cep),
        street_name: String(endereco.endereco ?? "").trim(),
        street_number: "",
      };
    }

    // ---- Monta a preference -------------------------------------------
    const webhook = `${SUPABASE_URL}/functions/v1/webhook-mercadopago`;
    const descricaoItem = produto.descricao_curta || produto.descricao ||
      produto.nome;
    const pref: Record<string, unknown> = {
      items: [{
        id: String(produto.id),
        title: produto.nome,
        description: String(descricaoItem).slice(0, 250),
        category_id: produto.tipo === "fisico" ? "others" : "virtual_goods",
        quantity: 1,
        currency_id: "BRL",
        unit_price: Number(produto.preco),
      }],
      payer,
      external_reference: pedido.id, // liga o pagamento ao nosso pedido
      notification_url: webhook,
      statement_descriptor: STATEMENT_DESCRIPTOR,
      metadata: { pedido_id: pedido.id, produto_id: produto.id },
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
