// =====================================================================
//  admin-clientes  (somente administradores)
//  Ações:
//    - listar         : lista os clientes cadastrados (contas de login)
//    - definir_senha  : define uma nova senha para um cliente
//    - enviar_reset   : envia e-mail de redefinição de senha ao cliente
//
//  Senhas NUNCA são retornadas (são criptografadas e não podem ser lidas).
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors, json } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erro: "Método inválido" }, 405);

  try {
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json({ erro: "Sem login" }, 401);

    // quem está chamando?
    const comUsuario = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: auth } },
    });
    const { data: userData } = await comUsuario.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ erro: "Sessão inválida" }, 401);

    const db = createClient(SUPABASE_URL, SERVICE_ROLE);

    // é admin?
    const { data: adm } = await db.from("administradores").select("user_id").eq(
      "user_id",
      user.id,
    ).maybeSingle();
    if (!adm) return json({ erro: "Acesso restrito a administradores" }, 403);

    const { acao, user_id, email, senha } = await req.json();

    if (acao === "listar") {
      // clientes = usuários que NÃO são admins
      const { data: admins } = await db.from("administradores").select(
        "user_id",
      );
      const idsAdmin = new Set((admins ?? []).map((a) => a.user_id));

      const clientes: any[] = [];
      let page = 1;
      while (true) {
        const { data, error } = await db.auth.admin.listUsers({
          page,
          perPage: 200,
        });
        if (error) return json({ erro: error.message }, 500);
        for (const u of data.users) {
          if (idsAdmin.has(u.id)) continue;
          clientes.push({
            id: u.id,
            email: u.email,
            criado_em: u.created_at,
            ultimo_acesso: u.last_sign_in_at,
            confirmado: !!u.email_confirmed_at,
          });
        }
        if (data.users.length < 200) break;
        page++;
        if (page > 25) break; // trava de segurança (até ~5000)
      }
      return json({ clientes });
    }

    if (acao === "definir_senha") {
      if (!user_id || !senha || String(senha).length < 6) {
        return json({ erro: "Informe o usuário e uma senha (mín. 6)" }, 400);
      }
      const { error } = await db.auth.admin.updateUserById(user_id, {
        password: String(senha),
      });
      if (error) return json({ erro: error.message }, 500);
      return json({ ok: true });
    }

    if (acao === "enviar_reset") {
      if (!email) return json({ erro: "Informe o e-mail" }, 400);
      const { error } = await comUsuario.auth.resetPasswordForEmail(email);
      if (error) return json({ erro: error.message }, 500);
      return json({ ok: true });
    }

    return json({ erro: "Ação desconhecida" }, 400);
  } catch (err) {
    return json({ erro: String(err?.message ?? err) }, 500);
  }
});
