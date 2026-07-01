/* =====================================================================
 *  Sacola (carrinho) compartilhada — Universo Católico Kids
 *  ---------------------------------------------------------------------
 *  Guarda os itens no localStorage e finaliza TUDO num pagamento só,
 *  chamando a Edge Function criar-pagamento (que aceita "itens").
 *
 *  Uso nas páginas:
 *    <script src="../config.js"></script>
 *    <script src="../assets/sacola.js"></script>
 *    ...
 *    Sacola.add({ id, nome, preco, tipo, frete, capa_url, capa_cor1, capa_cor2 })
 *
 *  Um botão flutuante com o número de itens aparece sozinho.
 * ===================================================================== */
(function () {
  const CFG = window.UCK_CONFIG || {};
  const KEY = "uck_sacola_v1";
  const brl = (n) => "R$ " + (Number(n) || 0).toFixed(2).replace(".", ",");
  const esc = (s) =>
    String(s == null ? "" : s).replace(
      /[&<>"]/g,
      (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]),
    );

  /* ---------- estado (localStorage) ---------- */
  function ler() {
    try {
      return JSON.parse(localStorage.getItem(KEY)) || [];
    } catch (_) {
      return [];
    }
  }
  function gravar(l) {
    localStorage.setItem(KEY, JSON.stringify(l));
    pintarBadge();
  }
  function contar() {
    return ler().length;
  }
  function totais() {
    const l = ler();
    const sub = l.reduce((s, x) => s + (Number(x.preco) || 0), 0);
    const frete = l.filter((x) => x.tipo === "fisico")
      .reduce((s, x) => s + (Number(x.frete) || 0), 0);
    return { sub, frete, total: sub + frete, temFisico: l.some((x) => x.tipo === "fisico") };
  }

  function add(p) {
    if (!p || !p.id) return;
    const tipo = p.tipo || "infoproduto";
    if (tipo === "externo") return; // produto externo não entra na sacola
    const l = ler();
    if (l.some((x) => x.id === p.id)) {
      toast("Este item já está na sacola");
      abrir();
      return;
    }
    l.push({
      id: p.id,
      nome: p.nome,
      preco: Number(p.preco) || 0,
      tipo,
      frete: Number(p.frete || 0),
      capa_url: p.capa_url || "",
      capa_cor1: p.capa_cor1 || "#2f8fd6",
      capa_cor2: p.capa_cor2 || "#1f57c3",
    });
    gravar(l);
    toast("Adicionado à sacola");
    abrir();
  }
  function remover(id) {
    gravar(ler().filter((x) => x.id !== id));
    render();
  }
  function limpar() {
    gravar([]);
  }

  /* ---------- CSS injetado ---------- */
  function injetarCss() {
    if (document.getElementById("scl-css")) return;
    const st = document.createElement("style");
    st.id = "scl-css";
    st.textContent = `
    .scl-fab{position:fixed;right:20px;bottom:20px;z-index:120;background:#1f57c3;color:#fff;border:0;
      width:58px;height:58px;border-radius:50%;box-shadow:0 10px 26px rgba(31,87,195,.4);cursor:pointer;
      display:flex;align-items:center;justify-content:center;transition:.15s}
    .scl-fab:hover{transform:translateY(-2px)}
    .scl-fab .n{position:absolute;top:-4px;right:-4px;background:#e8533f;color:#fff;font:800 12px/1 Nunito,sans-serif;
      min-width:22px;height:22px;border-radius:11px;display:flex;align-items:center;justify-content:center;padding:0 5px;border:2px solid #fff}
    .scl-ov{position:fixed;inset:0;background:rgba(20,30,60,.45);z-index:130;display:none;justify-content:flex-end}
    .scl-ov.on{display:flex}
    .scl-drawer{background:#f6f4ee;width:100%;max-width:420px;height:100%;display:flex;flex-direction:column;box-shadow:-10px 0 40px rgba(0,0,0,.25);font-family:Nunito,sans-serif;color:#28303f}
    .scl-head{padding:18px 20px;background:#fff;border-bottom:1px solid #eceadf;display:flex;align-items:center;justify-content:space-between}
    .scl-head b{font:800 18px/1 'Baloo 2',Nunito,sans-serif;color:#15418c}
    .scl-x{background:#f3f3ec;border:0;width:34px;height:34px;border-radius:50%;font-size:18px;color:#7c8091;cursor:pointer}
    .scl-itens{flex:1;overflow:auto;padding:14px 16px;display:flex;flex-direction:column;gap:10px}
    .scl-item{background:#fff;border:1px solid #eceadf;border-radius:14px;padding:11px;display:flex;gap:11px;align-items:center}
    .scl-cap{width:46px;height:46px;border-radius:10px;flex-shrink:0;background-size:cover;background-position:center}
    .scl-item .inf{flex:1;min-width:0}
    .scl-item .inf b{display:block;font-size:14px;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .scl-item .inf span{font-size:12px;color:#7c8091;font-weight:700}
    .scl-item .pr{font:800 15px/1 'Baloo 2',Nunito,sans-serif;color:#2fa15a;white-space:nowrap}
    .scl-del{background:none;border:0;color:#e8533f;font-weight:800;font-size:12px;cursor:pointer;padding:4px}
    .scl-vazio{text-align:center;color:#7c8091;padding:50px 20px;font-weight:700}
    .scl-foot{background:#fff;border-top:1px solid #eceadf;padding:16px 18px}
    .scl-lin{display:flex;justify-content:space-between;font-size:14px;margin-bottom:6px;color:#54596a;font-weight:700}
    .scl-tot{display:flex;justify-content:space-between;font:800 20px/1 'Baloo 2',Nunito,sans-serif;color:#15418c;margin:8px 0 14px}
    .scl-btn{border:0;border-radius:12px;padding:13px;font:800 15px/1 Nunito,sans-serif;width:100%;cursor:pointer;color:#fff;
      background:linear-gradient(150deg,#37b866,#2f9a54);box-shadow:0 8px 20px rgba(47,161,90,.3)}
    .scl-btn:disabled{opacity:.6;cursor:default}
    .scl-campo{margin-bottom:11px}
    .scl-campo label{display:block;font-weight:800;font-size:13px;margin-bottom:5px}
    .scl-campo input{width:100%;padding:11px 12px;border:1.5px solid #eceadf;border-radius:10px;background:#fcfcf9;font:15px Nunito,sans-serif}
    .scl-campo input:focus{outline:0;border-color:#1f57c3;background:#fff}
    .scl-erro{background:#fdecea;color:#e8533f;font-weight:700;font-size:13px;padding:9px 12px;border-radius:9px;margin-bottom:11px}
    .scl-seguro{text-align:center;font-size:12px;color:#7c8091;margin-top:11px}
    .scl-back{background:none;border:0;color:#1f57c3;font-weight:800;font-size:13px;cursor:pointer;margin-bottom:8px;padding:0}
    .scl-toast{position:fixed;bottom:90px;left:50%;transform:translateX(-50%);background:#15418c;color:#fff;padding:12px 20px;
      border-radius:12px;font:800 14px Nunito,sans-serif;z-index:200;box-shadow:0 10px 30px rgba(0,0,0,.25)}
    `;
    document.head.appendChild(st);
  }

  /* ---------- elementos base ---------- */
  let fab, ov;
  function garantirElementos() {
    injetarCss();
    if (!fab) {
      fab = document.createElement("button");
      fab.className = "scl-fab";
      fab.title = "Sacola";
      fab.innerHTML =
        `<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><path d="M3 6h18"/><path d="M16 10a4 4 0 0 1-8 0"/></svg><span class="n" style="display:none">0</span>`;
      fab.onclick = abrir;
      document.body.appendChild(fab);
    }
    if (!ov) {
      ov = document.createElement("div");
      ov.className = "scl-ov";
      ov.innerHTML = `<div class="scl-drawer" id="sclDrawer"></div>`;
      ov.onclick = (e) => {
        if (e.target === ov) fechar();
      };
      document.body.appendChild(ov);
    }
  }

  function pintarBadge() {
    if (!fab) return;
    const n = contar();
    const b = fab.querySelector(".n");
    b.textContent = n;
    b.style.display = n ? "flex" : "none";
  }

  /* ---------- render da gaveta ---------- */
  let modoCheckout = false;
  function abrir() {
    garantirElementos();
    modoCheckout = false;
    render();
    ov.classList.add("on");
  }
  function fechar() {
    if (ov) ov.classList.remove("on");
  }

  function render() {
    const d = document.getElementById("sclDrawer");
    if (!d) return;
    const l = ler();
    const t = totais();
    if (modoCheckout) {
      d.innerHTML = telaCheckout(t);
      ligarCheckout();
      return;
    }
    d.innerHTML = `
      <div class="scl-head"><b>Sua sacola</b><button class="scl-x" id="sclFechar">&times;</button></div>
      <div class="scl-itens">
        ${
      l.length
        ? l.map((x) => `
          <div class="scl-item">
            <div class="scl-cap" style="background:${
          x.capa_url
            ? `url('${esc(x.capa_url)}') center/cover`
            : `linear-gradient(160deg,${x.capa_cor1},${x.capa_cor2})`
        }"></div>
            <div class="inf"><b title="${esc(x.nome)}">${esc(x.nome)}</b>
              <span>${x.tipo === "fisico" ? "Livro físico" : "Acesso digital"}</span></div>
            <div style="text-align:right">
              <div class="pr">${brl(x.preco)}</div>
              <button class="scl-del" data-del="${esc(x.id)}">remover</button>
            </div>
          </div>`).join("")
        : `<div class="scl-vazio">Sua sacola está vazia.</div>`
    }
      </div>
      ${
      l.length
        ? `<div class="scl-foot">
        <div class="scl-lin"><span>Subtotal</span><span>${brl(t.sub)}</span></div>
        ${t.frete > 0 ? `<div class="scl-lin"><span>Frete</span><span>${brl(t.frete)}</span></div>` : ""}
        <div class="scl-tot"><span>Total</span><span>${brl(t.total)}</span></div>
        <button class="scl-btn" id="sclFinalizar">Finalizar compra</button>
      </div>`
        : ""
    }`;
    d.querySelector("#sclFechar").onclick = fechar;
    d.querySelectorAll("[data-del]").forEach((b) =>
      b.onclick = () => remover(b.dataset.del)
    );
    const fin = d.querySelector("#sclFinalizar");
    if (fin) {
      fin.onclick = () => {
        modoCheckout = true;
        render();
      };
    }
  }

  function telaCheckout(t) {
    return `
      <div class="scl-head"><b>Finalizar</b><button class="scl-x" id="sclFechar">&times;</button></div>
      <div class="scl-itens">
        <button class="scl-back" id="sclVoltar">&larr; Voltar para a sacola</button>
        <div id="sclErro" class="scl-erro" style="display:none"></div>
        <div class="scl-campo"><label>Seu nome ${t.temFisico ? "*" : ""}</label><input id="sclNome" placeholder="Nome completo"></div>
        <div class="scl-campo"><label>Seu e-mail *</label><input id="sclEmail" type="email" placeholder="usado para acessar os PDFs depois"></div>
        <div class="scl-campo"><label>CPF <span style="color:#7c8091;font-weight:600">(recomendado)</span></label><input id="sclCpf" inputmode="numeric" placeholder="000.000.000-00"></div>
        <div class="scl-campo"><label>Telefone ${t.temFisico ? "*" : '<span style="color:#7c8091;font-weight:600">(recomendado)</span>'}</label><input id="sclTel" placeholder="(00) 00000-0000"></div>
        ${
      t.temFisico
        ? `
          <div class="scl-campo"><label>CEP *</label><input id="sclCep" placeholder="00000-000"></div>
          <div class="scl-campo"><label>Endereço *</label><input id="sclEnd" placeholder="Rua, número, complemento"></div>
          <div class="scl-campo"><label>Cidade / UF *</label><input id="sclCidade" placeholder="Cidade - UF"></div>`
        : ""
    }
      </div>
      <div class="scl-foot">
        <div class="scl-tot"><span>Total</span><span>${brl(t.total)}</span></div>
        <button class="scl-btn" id="sclPagar">Ir para o pagamento</button>
        <div class="scl-seguro"><svg xmlns="http://www.w3.org/2000/svg" width="1.05em" height="1.05em" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-0.2em"><rect width="18" height="11" x="3" y="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg> Ambiente seguro do Mercado Pago</div>
      </div>`;
  }

  function ligarCheckout() {
    const d = document.getElementById("sclDrawer");
    d.querySelector("#sclFechar").onclick = fechar;
    d.querySelector("#sclVoltar").onclick = () => {
      modoCheckout = false;
      render();
    };
    d.querySelector("#sclPagar").onclick = pagar;
  }

  function mostrarErro(m) {
    const e = document.getElementById("sclErro");
    if (e) {
      e.textContent = m;
      e.style.display = "block";
    }
  }
  const val = (id) => (document.getElementById(id)?.value || "").trim();

  async function pagar() {
    const l = ler();
    const t = totais();
    if (!l.length) return;
    const email = val("sclEmail").toLowerCase();
    const nome = val("sclNome");
    const cpf = val("sclCpf");
    const telefone = val("sclTel");
    if (!email || !/.+@.+\..+/.test(email)) return mostrarErro("Digite um e-mail válido.");
    let endereco = null;
    if (t.temFisico) {
      const cep = val("sclCep"), end = val("sclEnd"), cidade = val("sclCidade");
      if (!nome || !telefone || !cep || !end || !cidade) {
        return mostrarErro("Para itens físicos, preencha nome, telefone e o endereço completo.");
      }
      endereco = { nome, telefone, cep, endereco: end, cidade };
    }
    if (!CFG.SUPABASE_URL || !CFG.SUPABASE_ANON_KEY) {
      return mostrarErro("Loja em configuração. Tente mais tarde.");
    }
    const btn = document.getElementById("sclPagar");
    btn.disabled = true;
    btn.textContent = "Gerando pagamento…";
    try {
      const r = await fetch(`${CFG.SUPABASE_URL}/functions/v1/criar-pagamento`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": CFG.SUPABASE_ANON_KEY,
          "Authorization": `Bearer ${CFG.SUPABASE_ANON_KEY}`,
        },
        body: JSON.stringify({
          itens: l.map((x) => ({ produto_id: x.id, quantidade: 1 })),
          email,
          nome,
          cpf,
          telefone,
          endereco,
        }),
      });
      const j = await r.json();
      if (!r.ok) throw new Error(j.erro || "Falha ao iniciar pagamento");
      const url = j.init_point || j.sandbox_init_point;
      if (!url) throw new Error("Link de pagamento não recebido");
      limpar();
      window.location.href = url;
    } catch (ex) {
      mostrarErro(ex.message || String(ex));
      btn.disabled = false;
      btn.textContent = "Ir para o pagamento";
    }
  }

  /* ---------- toast ---------- */
  let toastEl;
  function toast(m) {
    if (toastEl) toastEl.remove();
    toastEl = document.createElement("div");
    toastEl.className = "scl-toast";
    toastEl.textContent = m;
    document.body.appendChild(toastEl);
    setTimeout(() => {
      if (toastEl) {
        toastEl.style.transition = ".3s";
        toastEl.style.opacity = "0";
      }
    }, 1600);
    setTimeout(() => toastEl && toastEl.remove(), 2000);
  }

  /* ---------- init ---------- */
  function init() {
    garantirElementos();
    pintarBadge();
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  window.Sacola = { add, abrir, fechar, contar, limpar };
})();
