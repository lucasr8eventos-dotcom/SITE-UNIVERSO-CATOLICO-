// =====================================================================
//  webhook-mercadopago
//  O Mercado Pago chama esta função quando um pagamento muda de estado.
//  Se estiver "approved", liberamos o acesso do cliente ao produto e,
//  para infoprodutos, criamos a conta e ENVIAMOS UM E-MAIL AUTOMÁTICO
//  com o link para o cliente definir a senha e acessar o material.
//
//  IMPORTANTE: publique esta função SEM verificação de JWT
//  (supabase functions deploy webhook-mercadopago --no-verify-jwt),
//  porque quem chama é o Mercado Pago, não um usuário logado.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;
const MP_TOKEN = Deno.env.get("MP_ACCESS_TOKEN")!;
const SITE_URL = Deno.env.get("SITE_URL") ?? "";
// E-mail transacional (opcional, mas recomendado). Sem estes segredos, o
// acesso é liberado normalmente — só não sai o e-mail automático.
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const EMAIL_FROM = Deno.env.get("EMAIL_FROM") ?? "";

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

// Envia o e-mail de acesso via Resend. Se não estiver configurado, ignora.
async function enviarEmailAcesso(
  email: string,
  produtoNome: string,
  link: string,
) {
  if (!RESEND_API_KEY || !EMAIL_FROM) return; // e-mail não configurado
  const html = `
    <div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:0 auto;color:#28303f">
      <h2 style="color:#15418c">Compra aprovada! 🎉</h2>
      <p>Obrigado pela sua compra de <b>${produtoNome}</b>.</p>
      <p>Falta só 1 passo: crie sua senha de acesso e entre na sua área para
      baixar o material.</p>
      <p style="text-align:center;margin:28px 0">
        <a href="${link}" style="background:#1f57c3;color:#fff;text-decoration:none;
        font-weight:bold;padding:13px 26px;border-radius:10px;display:inline-block">
        Criar meu acesso</a>
      </p>
      <p style="font-size:13px;color:#7c8091">Se o botão não funcionar, copie e
      cole este link no navegador:<br>${link}</p>
      <p style="font-size:13px;color:#7c8091">Use sempre o mesmo e-mail desta
      compra (${email}) para acessar.</p>
    </div>`;
  try {
    await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: EMAIL_FROM,
        to: email,
        subject: `Seu acesso: ${produtoNome}`,
        html,
      }),
    });
  } catch (e) {
    console.error("falha ao enviar e-mail:", e);
  }
}

// Cria a conta (se ainda não existir) e envia o e-mail com o link de acesso.
async function onboardingCliente(db: any, email: string, produtoNome: string) {
  // Cria o usuário já confirmado. Se já existir, o erro é ignorado.
  await db.auth.admin.createUser({ email, email_confirm: true });

  // Gera um link do tipo "recovery": leva o cliente à tela de definir senha
  // da área do cliente (conta/index.html trata o evento PASSWORD_RECOVERY).
  const site = (SITE_URL || "").replace(/\/+$/, "");
  const redirectTo = /^https?:\/\//i.test(site) ? `${site}/conta/` : undefined;
  const { data, error } = await db.auth.admin.generateLink({
    type: "recovery",
    email,
    options: redirectTo ? { redirectTo } : undefined,
  });
  if (error) {
    console.error("falha ao gerar link de acesso:", error.message);
    return;
  }
  const link = data?.properties?.action_link;
  if (link) await enviarEmailAcesso(email, produtoNome, link);
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
    const valorPago = Number(pg.transaction_amount ?? 0);

    const db = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Localiza o pedido
    let pedido: any = null;
    if (pedidoId) {
      const { data } = await db.from("pedidos").select("*").eq("id", pedidoId)
        .maybeSingle();
      pedido = data;
    }
    if (!pedido) return new Response("pedido nao encontrado", { status: 200 });

    // Guarda o status ANTERIOR: só disparamos o onboarding na primeira vez
    // que o pedido vira "aprovado" (evita e-mail duplicado em reenvios do MP).
    const jaEstavaAprovado = pedido.status === "aprovado";

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

    // Segurança: só libera se o valor pago cobrir o valor do pedido
    // (tolerância de centavos). Evita liberar por pagamento parcial/manipulado.
    const pagouOk = valorPago >= Number(pedido.valor ?? 0) - 0.05;

    // Pagamento aprovado -> libera o acesso de CADA item infoproduto da sacola
    // (que tem PDFs). Produtos físicos ficam só registrados para você enviar.
    if (novoStatus === "aprovado" && pagouOk) {
      const email = (pedido.email || emailPagador).toLowerCase();

      // Itens da sacola; cai no formato antigo (1 produto) se não houver itens.
      const itens: any[] = Array.isArray(pedido.itens) && pedido.itens.length
        ? pedido.itens
        : (pedido.produto_id ? [{ produto_id: pedido.produto_id }] : []);
      const ids = [...new Set(itens.map((i) => i.produto_id).filter(Boolean))];

      let liberouAlgum = false;
      let nomeParaEmail = "seus materiais";
      if (ids.length) {
        // Confere o tipo no banco (não confia no que veio do cliente).
        const { data: prods } = await db
          .from("produtos")
          .select("id, tipo, nome")
          .in("id", ids);
        const mapa: Record<string, any> = Object.fromEntries(
          (prods ?? []).map((p) => [p.id, p]),
        );
        const digitais = (prods ?? []).filter((p) =>
          !p.tipo || p.tipo === "infoproduto"
        );
        if (digitais.length === 1) nomeParaEmail = digitais[0].nome;

        for (const it of itens) {
          const prod = mapa[it.produto_id];
          if (!prod || prod.tipo === "infoproduto") {
            await db.from("acessos").upsert({
              email,
              produto_id: it.produto_id,
              pedido_id: pedido.id,
              ativo: true,
            }, { onConflict: "email,produto_id" });
            liberouAlgum = true;
          }
        }
      }

      // Onboarding automático (conta + e-mail) só na primeira aprovação e
      // apenas se algum item digital foi liberado.
      if (!jaEstavaAprovado && email && liberouAlgum) {
        try {
          await onboardingCliente(db, email, nomeParaEmail);
        } catch (e) {
          console.error("onboarding falhou:", e);
        }
      }
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
