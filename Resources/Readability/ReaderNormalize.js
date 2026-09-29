// Makes every piece of readable text live inside a listen block (see ListenHTMLBlocks).
// Loose text in <div>s, <br><br>-separated lines, and the lead-in text of a list item or
// quote that also holds nested blocks get wrapped in <p>, so speech, tap, and highlight
// never skip them. Returns the normalized HTML.
function __readerNormalizeContent(html, listenSelector) {
  var LISTEN = {};
  listenSelector.split(',').forEach(function (t) { LISTEN[t.trim().toUpperCase()] = 1; });
  var BLOCK = {
    ADDRESS: 1, ARTICLE: 1, ASIDE: 1, CAPTION: 1, CENTER: 1, DETAILS: 1, DIALOG: 1, DIV: 1,
    DL: 1, FIELDSET: 1, FIGURE: 1, FOOTER: 1, FORM: 1, HEADER: 1, HR: 1, MAIN: 1, MENU: 1,
    NAV: 1, OL: 1, SECTION: 1, SUMMARY: 1, TABLE: 1, TBODY: 1, TFOOT: 1, THEAD: 1, TR: 1, UL: 1
  };
  Object.keys(LISTEN).forEach(function (k) { BLOCK[k] = 1; });
  var BLOCK_SEL = Object.keys(BLOCK).map(function (k) { return k.toLowerCase(); }).join(', ');
  // Block-level, or an inline wrapper around blocks (e.g. <a><div>…</div></a>).
  function actsAsBlock(n) {
    return n.nodeType === 1 && (BLOCK[n.tagName] || !!n.querySelector(BLOCK_SEL));
  }
  var NO_WRAP = { P: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1, PRE: 1, TABLE: 1, TBODY: 1,
    THEAD: 1, TFOOT: 1, TR: 1, UL: 1, OL: 1, DL: 1 };

  var box = document.createElement('div');
  box.innerHTML = html;
  box.querySelectorAll('script, style, noscript, template').forEach(function (el) { el.remove(); });

  function hasText(nodes) {
    for (var i = 0; i < nodes.length; i++) {
      if ((nodes[i].textContent || '').replace(/\u00a0/g, ' ').trim()) return true;
    }
    return false;
  }
  function isBR(n) { return n && n.nodeType === 1 && n.tagName === 'BR'; }
  function isBlank(n) { return n.nodeType === 3 && !n.nodeValue.replace(/\u00a0/g, ' ').trim(); }

  // Wrap each run of inline children that carries text into its own <p>.
  // Runs break at block children and at <br><br>.
  function wrapRuns(el) {
    var runs = [], cur = [], drop = [];
    var kids = Array.prototype.slice.call(el.childNodes);
    for (var i = 0; i < kids.length; i++) {
      var n = kids[i];
      if (actsAsBlock(n)) { runs.push(cur); cur = []; continue; }
      if (isBR(n)) {
        var j = i + 1;
        while (j < kids.length && isBlank(kids[j])) j++;
        if (isBR(kids[j])) {
          runs.push(cur); cur = [];
          for (var k = i; k <= j; k++) drop.push(kids[k]);
          i = j;
          continue;
        }
      }
      if (n.nodeType === 1 || n.nodeType === 3) cur.push(n);
    }
    runs.push(cur);
    runs.forEach(function (run) {
      while (run.length && (isBlank(run[0]) || isBR(run[0]))) run.shift();
      while (run.length && (isBlank(run[run.length - 1]) || isBR(run[run.length - 1]))) run.pop();
      if (!run.length || !hasText(run)) return;
      var p = document.createElement('p');
      el.insertBefore(p, run[0]);
      run.forEach(function (n) { p.appendChild(n); });
    });
    drop.forEach(function (n) { if (n.parentNode === el) n.remove(); });
  }

  function visit(el, covered) {
    var isListen = !!LISTEN[el.tagName];
    var nowCovered = covered || isListen;
    var hasListenInside = !!el.querySelector(listenSelector);
    // Text here is lost unless wrapped when a nested block steals leaf status,
    // or when no listen block covers it at all.
    if ((hasListenInside || !nowCovered) && !NO_WRAP[el.tagName]) wrapRuns(el);
    for (var c = el.firstElementChild; c; c = c.nextElementSibling) {
      if (actsAsBlock(c)) visit(c, nowCovered);
    }
  }
  visit(box, false);
  return box.innerHTML;
}
