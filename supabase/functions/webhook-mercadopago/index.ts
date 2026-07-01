// =====================================================================
//  webhook-mercadopago
//  O Mercado Pago chama esta função quando um pagamento muda de estado.
//  Se estiver "approved", liberamos o acesso do cliente ao produto.
//
//  IMPORTANTE: publique esta função SEM verificação de JWT
//  (supabase functions deploy webhook-mercadopago --no-verify-jwt),
//  porque quem chama é o Mercado Pago, não um usuário logado.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;
const MP_TOKEN = Deno.env.get("MP_ACCESS_TOKEN")!;

// Descobre o ID do pagamento em qualquer um dos formatos que o MP usa.
function extrairPaymentId(url: URL, body: any): string | null {
  const tipo = url.searchParams.get("type") ?? url.searchParams.get("topic") ??
    body?.type ?? body?.topic;
  const idQuery = url.searchParams.get("data.id") ??
    url.searchParams.get("id");
  const idBody = body?.data?.id ?? body?.id;
  const id = idBody ?? idQuery;
  if (!id) return null;
  // só nos interessa notificação de pagamento
  if (tipo && !String(tipo).includes("payment")) return null;
  return String(id);
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    let body: any = {};
    try {
      body = await req.json();
    } catch (_) { /* pode vir sem corpo */ }

    const paymentId = extrairPaymentId(url, body);
    // Sempre respondemos 200 rápido: se não for pagamento, ignoramos.
    if (!paymentId) return new Response("ignorado", { status: 200 });

    // Consulta o pagamento real no Mercado Pago (fonte da verdade)
    const r = await fetch(
      `https://api.mercadopago.com/v1/payments/${paymentId}`,
      { headers: { "Authorization": `Bearer ${MP_TOKEN}` } },
    );
    if (!r.ok) return new Response("pagamento nao encontrado", { status: 200 });
    const pg = await r.json();

    const pedidoId = pg.external_reference as string | undefined;
    const status = pg.status as string; // approved | pending | rejected | refunded...
    const emailPagador = (pg.payer?.email ?? "").toLowerCase();

    const db = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Localiza o pedido
    let pedido: any = null;
    if (pedidoId) {
      const { data } = await db.from("pedidos").select("*").eq("id", pedidoId)
        .maybeSingle();
      pedido = data;
    }
    if (!pedido) return new Response("pedido nao encontrado", { status: 200 });

    const mapa: Record<string, string> = {
      approved: "aprovado",
      pending: "pendente",
      in_process: "pendente",
      authorized: "pendente",
      rejected: "recusado",
      cancelled: "recusado",
      refunded: "estornado",
      charged_back: "estornado",
    };
    const novoStatus = mapa[status] ?? "pendente";

    await db.from("pedidos").update({
      status: novoStatus,
      mp_payment_id: String(paymentId),
    }).eq("id", pedido.id);

    // Pagamento aprovado -> libera o acesso (idempotente por unique email+produto)
    if (novoStatus === "aprovado") {
      const email = pedido.email || emailPagador;
      await db.from("acessos").upsert({
        email,
        produto_id: pedido.produto_id,
        pedido_id: pedido.id,
        ativo: true,
      }, { onConflict: "email,produto_id" });
    }

    // Acesso estornado/cancelado -> revoga
    if (novoStatus === "estornado") {
      await db.from("acessos").update({ ativo: false }).eq(
        "pedido_id",
        pedido.id,
      );
    }

    return new Response("ok", { status: 200 });
  } catch (err) {
    // Devolve 200 mesmo em erro para o MP não ficar reenviando infinitamente;
    // o erro fica nos logs da função.
    console.error("webhook erro:", err);
    return new Response("erro tratado", { status: 200 });
  }
});
