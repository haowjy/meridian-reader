// Serializes the live page without short text the reader can't actually see.
// Anti-copy injections (e.g. Royal Road's "this story is on Amazon without permission"
// spans hidden by a random CSS class) disappear from the saved article and from speech.
// Large hidden regions are kept: they're usually collapsed UI (mobile Wikipedia sections),
// not injected text.
function __readerVisibleSnapshot() {
  var root = document.documentElement || document.body;
  if (!root) return '';
  var body = document.body;
  var MARK = 'data-reader-hidden';
  var MAX_HIDDEN_TEXT = 300;
  var SKIP = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEMPLATE: 1, HEAD: 1, svg: 1, SVG: 1 };
  var sx = window.scrollX || 0, sy = window.scrollY || 0;

  function directText(el) {
    for (var n = el.firstChild; n; n = n.nextSibling) {
      if (n.nodeType === 3 && n.nodeValue.replace(/\u00a0/g, ' ').trim()) return true;
    }
    return false;
  }

  function isHidden(el) {
    var cs = window.getComputedStyle(el);
    if (!cs) return false;
    if (cs.display === 'none') return true;
    if (cs.visibility === 'hidden' || cs.visibility === 'collapse') return true;
    if (parseFloat(cs.opacity) === 0) return true;
    if (cs.clipPath === 'inset(50%)' || /rect\(\s*0(px)?[\s,]+0(px)?[\s,]+0(px)?[\s,]+0(px)?\s*\)/.test(cs.clip)) return true;
    var r = el.getBoundingClientRect();
    if ((cs.position === 'absolute' || cs.position === 'fixed') &&
        (r.right + sx < -50 || r.bottom + sy < -50)) return true;
    if (cs.overflow === 'hidden' && r.width <= 1 && r.height <= 1) return true;
    if (directText(el)) {
      if (parseFloat(cs.fontSize) < 1) return true;
      if (/rgba\([^)]*,\s*0\)$/.test(cs.color) || cs.color === 'transparent') return true;
    }
    return false;
  }

  // Read-only pass first (no DOM writes, so style/layout isn't invalidated mid-walk).
  var hidden = [];
  function walk(el) {
    for (var c = el.firstElementChild; c; c = c.nextElementSibling) {
      if (SKIP[c.tagName]) continue;
      if (isHidden(c)) {
        // Short hidden text is removed. Large hidden regions are left intact and not
        // descended into (their children report misleading styles and zero-size boxes).
        var text = (c.textContent || '').replace(/\s+/g, ' ').trim();
        if (text.length <= MAX_HIDDEN_TEXT) hidden.push(c);
        continue;
      }
      walk(c);
    }
  }
  if (body) walk(body);

  if (!hidden.length) return root.outerHTML;
  hidden.forEach(function (el) { el.setAttribute(MARK, '1'); });
  var clone = root.cloneNode(true);
  hidden.forEach(function (el) { el.removeAttribute(MARK); });
  clone.querySelectorAll('[' + MARK + ']').forEach(function (el) { el.remove(); });
  return clone.outerHTML;
}
