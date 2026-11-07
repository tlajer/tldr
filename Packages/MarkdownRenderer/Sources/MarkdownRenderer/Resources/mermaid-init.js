// Renders ```mermaid blocks with a theme that follows the system appearance.
// The host awaits window.tldrReady before restoring scroll position or showing a preview.
(() => {
  const blocks = [...document.querySelectorAll("pre.mermaid")];
  const sources = blocks.map((b) => b.textContent);
  const dark = matchMedia("(prefers-color-scheme: dark)");
  const report = (msg) => window.webkit?.messageHandlers?.tldr?.postMessage(msg);

  async function render() {
    document.documentElement.classList.add("mermaid-loading");
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: dark.matches ? "dark" : "default",
      fontFamily: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif",
    });
    blocks.forEach((b, i) => {
      b.removeAttribute("data-processed");
      b.textContent = sources[i];
    });
    // Parse first so invalid blocks keep their source (shown as code with the error)
    // instead of Mermaid's own "syntax error" graphic.
    const valid = [];
    for (const [i, b] of blocks.entries()) {
      try {
        await mermaid.parse(sources[i]);
        valid.push(b);
        b.classList.remove("mermaid-failed");
      } catch (e) {
        const message = String(e?.message ?? e).split("\n")[0].slice(0, 200);
        b.dataset.error = message;
        b.classList.add("mermaid-failed");
        report("mermaid parse error: " + message);
      }
    }
    try {
      await mermaid.run({ nodes: valid, suppressErrors: true });
    } catch (e) {
      report("mermaid error: " + e);
    }
    document.documentElement.classList.remove("mermaid-loading");
    report("mermaid rendered " + blocks.filter((b) => b.querySelector("svg")).length + "/" + blocks.length);
  }

  window.tldrReady = render();
  dark.addEventListener("change", () => { window.tldrReady = render(); });
})();
