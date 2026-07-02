/* =====================================================================
 *  Google Analytics 4 — Universo Católico Kids
 *  ---------------------------------------------------------------------
 *  Só carrega se GA_MEASUREMENT_ID estiver preenchido no config.js
 *  (ex.: "G-ABC123XYZ"). Sem ID, este arquivo não faz nada — zero peso.
 *
 *  Como ativar:
 *   1. Crie a propriedade em https://analytics.google.com (GA4)
 *   2. Copie o "ID da métrica" (começa com G-)
 *   3. Cole no config.js:  GA_MEASUREMENT_ID: "G-SEU_ID"
 * ===================================================================== */
(function () {
  var CFG = window.UCK_CONFIG || {};
  var id = CFG.GA_MEASUREMENT_ID;
  if (!id || !/^G-[A-Z0-9]+$/i.test(id)) return;
  var s = document.createElement("script");
  s.async = true;
  s.src = "https://www.googletagmanager.com/gtag/js?id=" + id;
  document.head.appendChild(s);
  window.dataLayer = window.dataLayer || [];
  function gtag() { dataLayer.push(arguments); }
  window.gtag = gtag;
  gtag("js", new Date());
  gtag("config", id, { anonymize_ip: true });
})();
