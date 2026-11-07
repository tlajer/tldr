enum Stylesheet {
    static let css = """
    :root {
      --fg: #1f2328; --fg-muted: #59636e; --bg: #ffffff; --bg-subtle: #f6f8fa;
      --border: #d1d9e0; --border-muted: #d1d9e0b3; --link: #0969da; --code-bg: #818b981f;
      --note: #0969da; --tip: #1a7f37; --important: #8250df; --warning: #9a6700; --caution: #d1242f;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --fg: #f0f6fc; --fg-muted: #9198a1; --bg: #0d1117; --bg-subtle: #151b23;
        --border: #3d444d; --border-muted: #3d444db3; --link: #4493f8; --code-bg: #656c7633;
        --note: #4493f8; --tip: #3fb950; --important: #ab7df8; --warning: #d29922; --caution: #f85149;
      }
    }
    html { background: var(--bg); }
    body {
      margin: 0; padding: 32px 40px 64px; color: var(--fg); background: var(--bg);
      font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
      -webkit-font-smoothing: antialiased; word-wrap: break-word;
    }
    .markdown-body { max-width: 860px; margin: 0 auto; }
    .markdown-body > :first-child { margin-top: 0 !important; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    p, blockquote, ul, ol, dl, table, pre, details, .alert { margin: 0 0 16px; }
    h1, h2, h3, h4, h5, h6 { position: relative; margin: 24px 0 16px; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border-muted); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border-muted); }
    h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .875em; }
    h6 { font-size: .85em; color: var(--fg-muted); }
    .anchor { position: absolute; left: -24px; padding-right: 4px; opacity: 0; }
    .anchor::before { content: "#"; color: var(--fg-muted); font-weight: 400; }
    h1:hover .anchor, h2:hover .anchor, h3:hover .anchor, h4:hover .anchor, h5:hover .anchor, h6:hover .anchor { opacity: 1; text-decoration: none; }
    hr { height: 4px; margin: 24px 0; padding: 0; border: 0; background: var(--border); border-radius: 2px; }
    blockquote { padding: 0 1em; color: var(--fg-muted); border-left: .25em solid var(--border); }
    blockquote > :last-child, .alert > :last-child, li > :last-child { margin-bottom: 0; }
    ul, ol { padding-left: 2em; }
    li + li { margin-top: .25em; }
    li > p { margin-top: 16px; }
    ul ul, ul ol, ol ol, ol ul { margin-top: .25em; margin-bottom: 0; }
    ul.task-list { list-style: none; padding-left: 1.4em; }
    .task-list-item input { margin: 0 .3em .25em -1.4em; vertical-align: middle; }
    code, pre { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 85%; }
    code { padding: .2em .4em; background: var(--code-bg); border-radius: 6px; }
    pre { padding: 16px; overflow: auto; line-height: 1.45; background: var(--bg-subtle); border-radius: 6px; }
    pre code { padding: 0; font-size: 100%; background: transparent; border-radius: 0; white-space: pre; }
    table { display: block; width: max-content; max-width: 100%; overflow: auto; border-spacing: 0; border-collapse: collapse; }
    th, td { padding: 6px 13px; border: 1px solid var(--border); }
    th { font-weight: 600; }
    tr { background: var(--bg); border-top: 1px solid var(--border-muted); }
    tbody tr:nth-child(2n) { background: var(--bg-subtle); }
    img { max-width: 100%; box-sizing: border-box; background: transparent; }
    kbd {
      display: inline-block; padding: 3px 5px; font: 11px ui-monospace, "SF Mono", Menlo, monospace;
      line-height: 10px; color: var(--fg); vertical-align: middle; background: var(--bg-subtle);
      border: 1px solid var(--border); border-radius: 6px; box-shadow: inset 0 -1px 0 var(--border);
    }
    .alert { padding: 8px 16px; border-left: .25em solid var(--alert); }
    .alert-title { display: flex; align-items: center; font-weight: 600; color: var(--alert); margin-bottom: 4px; }
    .alert-note { --alert: var(--note); } .alert-tip { --alert: var(--tip); }
    .alert-important { --alert: var(--important); } .alert-warning { --alert: var(--warning); }
    .alert-caution { --alert: var(--caution); }
    pre.mermaid { background: transparent; text-align: center; font-family: inherit; }
    pre.mermaid svg { max-width: 100%; height: auto; }
    pre.mermaid.mermaid-failed { text-align: left; background: var(--bg-subtle); font-family: ui-monospace, "SF Mono", Menlo, monospace; }
    pre.mermaid.mermaid-failed::before {
      content: "Mermaid: " attr(data-error); display: block; margin-bottom: 8px;
      color: var(--caution); font: 600 12px -apple-system, BlinkMacSystemFont, sans-serif;
    }
    .mermaid-loading pre.mermaid { visibility: hidden; }
    .front-matter { color: var(--fg-muted); font-size: 85%; }
    .front-matter summary { cursor: pointer; margin-bottom: 8px; }
    @media print { body { padding: 0; } }
    """ + dataCSS

    /// JSON/XML tree view (DataRenderer).
    static let dataCSS = """
    :root {
      --syn-key: #0550ae; --syn-str: #0a3069; --syn-num: #953800; --syn-lit: #cf222e;
      --syn-tag: #116329; --syn-com: #6e7781; --hover: #818b9826; --err-bg: #ffebe9;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --syn-key: #79c0ff; --syn-str: #a5d6ff; --syn-num: #ffa657; --syn-lit: #ff7b72;
        --syn-tag: #7ee787; --syn-com: #8b949e; --hover: #656c7633; --err-bg: #f851491a;
      }
    }
    body.data { padding: 0 0 32px; font: 12.5px/1.55 ui-monospace, "SF Mono", Menlo, monospace; }
    .data .bar {
      position: sticky; top: 0; z-index: 2; display: flex; align-items: center; gap: 8px;
      padding: 6px 16px; background: var(--bg-subtle); border-bottom: 1px solid var(--border-muted);
      font: 12px -apple-system, BlinkMacSystemFont, sans-serif; color: var(--fg-muted);
    }
    .data .badge { padding: 1px 7px; border-radius: 10px; background: var(--link); color: var(--bg); font-weight: 600; }
    .data .badge.muted { background: var(--code-bg); color: var(--fg-muted); font-weight: 400; }
    .data .meta { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .data .spacer { flex: 1; }
    .data .bar button {
      font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--border);
      border-radius: 6px; padding: 1px 9px; cursor: pointer;
    }
    .data .bar button:hover { background: var(--hover); }
    .data .error, .data .notice { margin: 12px 16px 0; padding: 8px 12px; border-radius: 6px; font: 13px -apple-system, sans-serif; }
    .data .error { background: var(--err-bg); border: 1px solid var(--caution); color: var(--fg); }
    .data .notice { background: var(--bg-subtle); color: var(--fg-muted); }
    .tree { padding: 12px 16px; }
    .show-raw .tree { display: none; }
    .tree .n { white-space: pre-wrap; word-break: break-word; margin: 0; }
    .tree summary { list-style: none; cursor: default; position: relative; }
    .tree summary::-webkit-details-marker { display: none; }
    .tree summary::before {
      content: "▸"; position: absolute; left: -13px; width: 12px; color: var(--fg-muted);
      cursor: pointer; transition: transform .1s; text-align: center;
    }
    .tree details[open] > summary::before { transform: rotate(90deg); }
    .tree details:not([open]) > summary { cursor: pointer; }
    .tree details[open] > summary .sum { display: none; }
    .tree summary:hover, .tree div.n:hover { background: var(--hover); border-radius: 3px; }
    .tree .ch { margin-left: 5px; padding-left: 17px; border-left: 1px solid var(--border-muted); }
    .tree .c { color: var(--fg-muted); font-style: italic; }
    .tree .p { color: var(--fg-muted); }
    .tree .k, .tree .a { color: var(--syn-key); cursor: copy; }
    .tree .t { color: var(--syn-tag); cursor: copy; }
    .tree .i { color: var(--fg-muted); opacity: .6; cursor: copy; margin-right: 1.2ch; user-select: none; }
    .tree .s, .tree .v { color: var(--syn-str); cursor: copy; }
    .tree .s a { color: inherit; text-decoration: underline; text-decoration-color: var(--border); }
    .tree .num { color: var(--syn-num); cursor: copy; }
    .tree .bool, .tree .null { color: var(--syn-lit); cursor: copy; }
    .tree .txt { color: var(--fg); cursor: copy; }
    .tree .com { color: var(--syn-com); font-style: italic; cursor: copy; }
    .tree .pi { color: var(--syn-com); }
    .tree .k:hover, .tree .t:hover, .tree .a:hover, .tree .i:hover, .tree .s:hover, .tree .v:hover,
    .tree .num:hover, .tree .bool:hover, .tree .null:hover, .tree .txt:hover { text-decoration: underline dotted; }
    pre.raw { display: none; margin: 0; padding: 12px 0; background: transparent; font-size: 100%; border-radius: 0; counter-reset: line; }
    .show-raw pre.raw { display: block; }
    pre.raw .line { display: block; padding-right: 16px; }
    pre.raw .line::before {
      counter-increment: line; content: counter(line); display: inline-block; width: 5ch; margin-right: 2ch;
      padding-right: 1ch; text-align: right; color: var(--fg-muted); opacity: .6; user-select: none;
    }
    pre.raw .line:target, pre.raw .line.err { background: var(--err-bg); }
    pre.raw .line.err::before { color: var(--caution); opacity: 1; }
    #status {
      position: fixed; left: 0; right: 0; bottom: 0; padding: 3px 16px; z-index: 2;
      background: var(--bg-subtle); border-top: 1px solid var(--border-muted); color: var(--fg-muted);
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    #status.flash { color: var(--tip); }
    .show-raw #status { display: none; }
    @media print { .data .bar, #status { display: none; } .data .tree details:not([open]) > .ch { display: block; } }
    """
}
