// =====================================================================
//  criar-pagamento
//  Recebe { produto_id, email, nome } do site, cria um PEDIDO (pendente)
//  e uma "preference" no Mercado Pago. Devolve o link do checkout.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors, json } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;
const MP_TOKEN = Deno.env.get("MP_ACCESS_TOKEN")!;
const SITE_URL = Deno.env.get("SITE_URL") ?? "";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erro: "Método inválido" }, 405);

  try {
    const { produto_id, email, nome, endereco } = await req.json();
    if (!produto_id || !email) {
      return json({ erro: "Informe produto_id e email" }, 400);
    }

    const db = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Busca o produto (preço vem do banco, nunca do cliente — segurança)
    const { data: produto, error: e1 } = await db
      .from("produtos")
      .select("id, nome, preco, ativo, tipo")
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

    // Cria o pedido pendente
    const { data: pedido, error: e2 } = await db
      .from("pedidos")
      .insert({
        produto_id: produto.id,
        email: String(email).toLowerCase().trim(),
        nome: nome ?? null,
        valor: produto.preco,
        status: "pendente",
        endereco: endereco ?? null,
      })
      .select("id")
      .single();
    if (e2 || !pedido) return json({ erro: "Falha ao criar pedido" }, 500);

    // Cria a preference no Mercado Pago
    const webhook = `${SUPABASE_URL}/functions/v1/webhook-mercadopago`;
    const pref = {
      items: [{
        title: produto.nome,
        quantity: 1,
        currency_id: "BRL",
        unit_price: Number(produto.preco),
      }],
      payer: { email: String(email).toLowerCase().trim() },
      external_reference: pedido.id, // liga o pagamento ao nosso pedido
      notification_url: webhook,
      back_urls: {
        success: `${SITE_URL}/conta/?compra=sucesso`,
        pending: `${SITE_URL}/conta/?compra=pendente`,
        failure: `${SITE_URL}/conta/?compra=falha`,
      },
      auto_return: "approved",
    };

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
