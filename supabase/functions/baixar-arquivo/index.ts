// =====================================================================
//  baixar-arquivo
//  O cliente LOGADO pede o download de um PDF. Conferimos se ele comprou
//  o produto e, só então, geramos um link temporário (expira em 5 min).
//  Assim o PDF fica num bucket privado e o link não pode ser repassado.
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors, json } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const BUCKET = "produtos-pdf";
const EXPIRA_SEG = 300; // 5 minutos

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erro: "Método inválido" }, 405);

  try {
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json({ erro: "Sem login" }, 401);

    const { arquivo_id } = await req.json();
    if (!arquivo_id) return json({ erro: "Informe arquivo_id" }, 400);

    // Identifica o usuário a partir do token dele
    const comUsuario = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: auth } },
    });
    const { data: userData } = await comUsuario.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ erro: "Sessão inválida" }, 401);
    const email = (user.email ?? "").toLowerCase();

    const db = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Qual produto é esse arquivo?
    const { data: arq, error: e1 } = await db
      .from("arquivos")
      .select("id, caminho, titulo, produto_id")
      .eq("id", arquivo_id)
      .single();
    if (e1 || !arq) return json({ erro: "Arquivo não encontrado" }, 404);

    // O usuário tem acesso a esse produto?
    const { data: acesso } = await db
      .from("acessos")
      .select("id")
      .eq("produto_id", arq.produto_id)
      .eq("ativo", true)
      .or(`user_id.eq.${user.id},email.eq.${email}`)
      .maybeSingle();

    // admin também pode
    const { data: admin } = await db
      .from("administradores")
      .select("user_id")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!acesso && !admin) {
      return json({ erro: "Você não tem acesso a este material" }, 403);
    }

    // Gera o link temporário do PDF privado
    const { data: assinado, error: e2 } = await db.storage
      .from(BUCKET)
      .createSignedUrl(arq.caminho, EXPIRA_SEG, { download: `${arq.titulo}.pdf` });
    if (e2 || !assinado) return json({ erro: "Falha ao gerar link" }, 500);

    return json({ url: assinado.signedUrl, titulo: arq.titulo });
  } catch (err) {
    return json({ erro: String(err?.message ?? err) }, 500);
  }
});
