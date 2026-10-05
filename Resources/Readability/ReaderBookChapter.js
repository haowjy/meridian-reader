// Prepares a book chapter (body-level XHTML cut from an EPUB) for __readerNormalizeContent: takes
// out what isn't text to read (pictures, embedded media, anything that would load a resource),
// footnotes and the note references that point at them, and unwraps links, since nothing in a
// chapter navigates. Parsed in an inert document, so nothing it names is fetched.
function __readerPrepareBookChapter(html) {
  var doc = document.implementation.createHTMLDocument('');
  var box = doc.createElement('div');
  box.innerHTML = html;
  var drop = [
    'script', 'style', 'noscript', 'template', 'link', 'meta', 'base', 'title',
    'img', 'picture', 'svg', 'video', 'audio', 'source', 'track', 'iframe', 'object', 'embed',
    'canvas', 'map', 'area',
    '[epub\\:type~="footnote"]', '[epub\\:type~="noteref"]',
    '[role~="doc-footnote"]', '[role~="doc-noteref"]'
  ].join(', ');
  box.querySelectorAll(drop).forEach(function (el) { el.remove(); });
  box.querySelectorAll('a').forEach(function (a) {
    while (a.firstChild) a.parentNode.insertBefore(a.firstChild, a);
    a.remove();
  });
  return box.innerHTML;
}
