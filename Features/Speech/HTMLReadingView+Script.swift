import Foundation

/// The script every reading page runs at document end (`HTMLReadingWebView.makeWebView`): it
/// numbers the listen blocks and gives Swift the page's side of tapping, highlighting, the
/// sentence underline and measuring.
extension HTMLReadingWebView {
    /// A paragraph's accessibility label in jump mode ("Paragraph 3") and its hint.
    static let jumpLabel = "Paragraph"
    static let jumpHint = "Plays from this paragraph"

    /// Injected from `ListenHTMLBlocks.innerSelector` so JS and Swift share one tag list.
    static var bootstrapJS: String {
        let sel = ListenHTMLBlocks.innerSelector
        return """
        (function() {
          var BLOCK_SEL = '\(sel)';
          var JUMP_LABEL = '\(jumpLabel)', JUMP_HINT = '\(jumpHint)';
          function textOf(el) {
            return (el.textContent || '').split(String.fromCharCode(160)).join(' ').trim();
          }
          // Leaf listen blocks — same tag list + leaf rule as ListenHTMLBlocks in Swift.
          function blocks() {
            return Array.from(document.body.querySelectorAll(BLOCK_SEL)).filter(function(el) {
              if (el.closest('.reader-heading')) return false;
              if (textOf(el).length === 0) return false;
              return !el.querySelector(BLOCK_SEL);
            });
          }
          function reindex() {
            document.body.querySelectorAll(BLOCK_SEL).forEach(function(el) {
              el.removeAttribute('data-reader-index');
              el.onclick = null;
              el.classList.remove('reader-active');
            });
            blocks().forEach(function(el, i) {
              el.setAttribute('data-reader-index', String(i));
              el.onclick = function(ev) {
                if (!window.__readerJump) return;
                ev.preventDefault();
                window.webkit.messageHandlers.readerBridge.postMessage({ index: i });
              };
            });
          }
          // A DOM range over [start, end) of the block's text in the session's coordinates: UTF-16
          // units of the text ListenHTMLBlocks reads from it (every character of its text nodes, a
          // <br> as one space, script / style skipped, leading whitespace dropped). A plain-text
          // paragraph is that text exactly, so its spaces, tabs and newlines all count too.
          function rangeIn(el, start, end) {
            var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
            var count = 0, leading = true, range = document.createRange(), started = false, node;
            while ((node = walker.nextNode())) {
              if (node.nodeType === Node.ELEMENT_NODE) {
                if (node.tagName !== 'BR' || leading) continue;
                if (!started && count >= start) { range.setStartBefore(node); started = true; }
                if (started && count >= end) { range.setEndBefore(node); return range; }
                count += 1;
                continue;
              }
              var parent = node.parentNode && node.parentNode.nodeName;
              if (parent === 'SCRIPT' || parent === 'STYLE') continue;
              var s = node.nodeValue;
              for (var i = 0; i < s.length; i++) {
                if (leading) {
                  if (/\\s/.test(s[i])) continue;
                  leading = false;
                }
                if (!started && count >= start) { range.setStart(node, i); started = true; }
                if (started && count >= end) { range.setEnd(node, i); return range; }
                count += 1;
              }
            }
            if (!started) return null;
            range.setEndAfter(el.lastChild || el);
            return range;
          }
          window.__readerJump = false;
          // While ☝︎ is on each paragraph is a button to assistive tech, "Paragraph N" with the hint
          // "Plays from this paragraph"; off, it reads as text again.
          window.__readerSetJumpMode = function(on) {
            window.__readerJump = !!on;
            document.body.classList.toggle('reader-jump', !!on);
            document.querySelectorAll('[data-reader-index]').forEach(function(el) {
              if (on) {
                el.setAttribute('role', 'button');
                el.setAttribute('aria-label', JUMP_LABEL + ' ' + (Number(el.getAttribute('data-reader-index')) + 1));
                el.setAttribute('aria-description', JUMP_HINT);
              } else {
                el.removeAttribute('role');
                el.removeAttribute('aria-label');
                el.removeAttribute('aria-description');
              }
            });
          };
          window.__readerSetActive = function(index) {
            var el = (index === null || index === undefined) ? null
              : document.querySelector('[data-reader-index="' + index + '"]');
            // Already highlighted: touching the class would still invalidate its style.
            if (el && el.classList.contains('reader-active')) return;
            document.querySelectorAll('.reader-active').forEach(function(other) {
              other.classList.remove('reader-active');
            });
            // Highlight only: scrolling is Swift's (following, scrub).
            if (el) el.classList.add('reader-active');
            // The rest dims only while a paragraph is spoken.
            document.body.classList.toggle('reader-has-active', !!el);
          };
          // Document y: what the scroll view calls content y.
          function docTop(rect) { return rect.top - document.documentElement.getBoundingClientRect().top; }
          // How far the article text starts below the top of the page's content.
          window.__readerTextTop = function() {
            var t = document.querySelector('.reader-text'); if (!t) return 0;
            var b = document.body;
            return t.getBoundingClientRect().top - b.getBoundingClientRect().top - parseFloat(getComputedStyle(b).paddingTop);
          };
          // The reading anchor at document y `y`: the first paragraph reaching below it, and the
          // session offset of the first character on its line there (0 when the paragraph starts
          // below `y`), with that line's top and the text's top. Index -1 on a page without
          // paragraphs.
          window.__readerAnchor = function(y) {
            var textTop = window.__readerTextTop();
            var els = document.querySelectorAll('[data-reader-index]');
            if (!els.length) return { index: -1, offset: 0, top: 0, textTop: textTop };
            var el = els[els.length - 1];
            for (var i = 0; i < els.length; i++) {
              var box = els[i].getBoundingClientRect();
              if (docTop(box) + box.height > y) { el = els[i]; break; }
            }
            var anchor = { index: Number(el.getAttribute('data-reader-index')), offset: 0,
                           top: docTop(el.getBoundingClientRect()), textTop: textTop };
            if (anchor.top >= y) return anchor;
            for (var n = 0; ; n++) {
              var r = rangeIn(el, n, n + 1);
              if (!r) break;
              var rect = r.getClientRects()[0]; // none for a space folded away at a line's end
              if (rect && docTop(rect) + rect.height > y) {
                anchor.offset = n;
                anchor.top = docTop(rect);
                break;
              }
            }
            return anchor;
          };
          // Where the anchor's line is now (after a reflow), with the text's top before and after:
          // [line before, line after, text top before, text top after].
          window.__readerAnchorMoved = function(a) {
            var after = window.__readerTextTop();
            var el = document.querySelector('[data-reader-index="' + a.index + '"]');
            if (!el) return [0, 0, a.textTop, after];
            var r = a.offset > 0 ? rangeIn(el, a.offset, a.offset + 1) : null;
            var rect = r && r.getClientRects()[0];
            return [a.top, rect ? docTop(rect) : docTop(el.getBoundingClientRect()), a.textTop, after];
          };
          // Where the spoken sentence (else, start null, its paragraph) sits: [document top, height,
          // the text's top]. The sentence's own line boxes: a range's bounding box can take in an
          // empty box at the start of the next line.
          window.__readerSpokenRect = function(index, start, end) {
            var el = document.querySelector('[data-reader-index="' + index + '"]');
            if (!el) return null;
            var box = el.getBoundingClientRect(), top = box.top, bottom = box.bottom;
            var range = (start === null || start === undefined) ? null : rangeIn(el, start, end);
            var lines = range ? Array.from(range.getClientRects()).filter(function(r) {
              return r.width > 0 && r.height > 0;
            }) : [];
            if (lines.length) {
              top = Math.min.apply(null, lines.map(function(r) { return r.top; }));
              bottom = Math.max.apply(null, lines.map(function(r) { return r.bottom; }));
            }
            return [docTop({ top: top }), bottom - top, window.__readerTextTop()];
          };
          window.__readerSetSentence = function(index, start, end) {
            if (!window.CSS || !CSS.highlights || typeof Highlight === 'undefined') return;
            CSS.highlights.delete('reader-sentence');
            if (index === null || index === undefined) return;
            var el = document.querySelector('[data-reader-index="' + index + '"]');
            var range = el && rangeIn(el, start, end);
            if (range) CSS.highlights.set('reader-sentence', new Highlight(range));
          };
          reindex();
          // The article's own leading heading already says the title: it takes the title's look,
          // and the source line moves under it (the heading stays a listen block, so numbering
          // doesn't change; the header isn't one wherever it sits).
          (function() {
            var title = document.querySelector('.reader-title');
            var first = blocks()[0];
            var norm = function(t) { return (t || '').replace(/\\s+/g, ' ').trim().toLowerCase(); };
            if (title && first && /^H[1-3]$/.test(first.tagName) && norm(first.textContent) === norm(title.textContent)) {
              title.style.display = 'none';
              first.classList.add('reader-title');
              first.parentNode.insertBefore(title.parentNode, first.nextSibling);
            }
          })();
        })();
        """
    }
}
