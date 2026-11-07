// Interaction for the JSON/XML tree rendered by DataRenderer.swift.
//
// click a key or tag   copy its path (jq for JSON, XPath for XML)
// click a value        copy the value
// ⌥-click a ▸          fold or unfold everything inside it
// E / C / 1–9          expand all, collapse all, fold to that level
// R                    toggle between tree and source
(() => {
  const tree = document.querySelector("main.tree");
  const status = document.getElementById("status");
  const isJSON = document.querySelector(".badge")?.textContent.startsWith("JSON");
  const post = (msg) => window.webkit?.messageHandlers?.tldr?.postMessage(msg);
  const identifier = /^[A-Za-z_][A-Za-z0-9_]*$/;
  window.tldrReady = Promise.resolve();

  function segment(node) {
    const d = node.dataset;
    if (isJSON) {
      if (d.i !== undefined) return `[${d.i}]`;
      if (d.k !== undefined) return identifier.test(d.k) ? `.${d.k}` : `[${JSON.stringify(d.k)}]`;
      return "";
    }
    return d.t === undefined ? "" : `/${d.t}${d.x ? `[${d.x}]` : ""}`;
  }

  function pathOf(el) {
    const parts = [];
    for (let n = el.closest(".n"); n; n = n.parentElement?.closest(".n")) parts.unshift(segment(n));
    let path = parts.join("");
    if (isJSON) return path.startsWith(".") ? path : "." + path;
    const attr = el.closest(".a");
    if (attr) path += `/@${attr.dataset.a}`;
    return path || "/";
  }

  function valueOf(el) {
    if (isJSON && el.classList.contains("s")) {
      try { return JSON.parse(el.textContent); } catch { /* fall through */ }
    }
    return el.textContent;
  }

  let hint = status.dataset.hint;
  let flashTimer;
  status.textContent = hint;
  function show(text) {
    if (!flashTimer) status.textContent = text;
  }
  function flash(text) {
    clearTimeout(flashTimer);
    status.textContent = text;
    status.classList.add("flash");
    flashTimer = setTimeout(() => {
      flashTimer = null;
      status.classList.remove("flash");
      status.textContent = hint;
    }, 1500);
  }
  function copy(text, what) {
    post({ copy: text });
    flash(`copied ${what}: ${text.length > 120 ? text.slice(0, 120) + "…" : text}`);
  }

  function setOpen(details, open) {
    details.forEach((d) => { d.open = open; });
  }
  function foldTo(level) {
    tree.querySelectorAll("details").forEach((d) => { d.open = Number(d.dataset.d) < level; });
  }

  tree.addEventListener("click", (e) => {
    if (e.target.closest("a")) return;
    const summary = e.target.closest("summary");
    if (e.altKey && summary) {
      e.preventDefault();
      const details = summary.parentElement;
      setOpen([details, ...details.querySelectorAll("details")], !details.open);
      return;
    }
    const key = e.target.closest(".k, .t, .a, .i");
    if (key) {
      e.preventDefault();
      copy(pathOf(key), "path");
      return;
    }
    const value = e.target.closest(".s, .num, .bool, .null, .v, .txt, .com");
    if (value) {
      e.preventDefault();
      copy(valueOf(value), "value");
    }
  });

  tree.addEventListener("mouseover", (e) => {
    const node = e.target.closest(".n");
    if (node) show(pathOf(e.target));
  });
  tree.addEventListener("mouseleave", () => show(hint));

  const actions = {
    expand: () => setOpen(tree.querySelectorAll("details"), true),
    collapse: () => foldTo(1),
    raw: () => document.body.classList.toggle("show-raw"),
  };
  document.querySelectorAll("header button[data-act]").forEach((b) => {
    b.addEventListener("click", () => actions[b.dataset.act]());
  });
  document.addEventListener("keydown", (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const key = e.key.toLowerCase();
    if (key === "e") actions.expand();
    else if (key === "c") actions.collapse();
    else if (key === "r") actions.raw();
    else if (key >= "1" && key <= "9") foldTo(Number(key));
    else return;
    e.preventDefault();
  });
})();
