// Parse TeX before Markdown can consume escapes, emphasis, or table content.
function noteMath(md) {
  const escaped = (src, pos) => {
    let n = 0;
    while (pos > 0 && src[--pos] === '\\') n++;
    return n % 2 === 1;
  };
  const render = (tex, displayMode) => {
    try {
      return katex.renderToString(tex, {
        displayMode, throwOnError: true, trust: false, strict: 'ignore',
        maxExpand: 1000, maxSize: 20, output: 'htmlAndMathml'
      });
    } catch (_) {
      return '<code class="math-error" title="Не удалось разобрать формулу">' + md.utils.escapeHtml(tex) + '</code>';
    }
  };
  md.inline.ruler.before('escape', 'note_math', (state, silent) => {
    const start = state.pos;
    const src = state.src;
    let open, close, display = false;
    if (src.startsWith('$$', start)) { open = close = '$$'; display = true; }
    else if (src[start] === '$') { open = close = '$'; }
    else if (src.startsWith('\\(', start)) { open = '\\('; close = '\\)'; }
    else if (src.startsWith('\\[', start)) { open = '\\['; close = '\\]'; display = true; }
    else return false;
    const from = start + open.length;
    if (open === '$' && /\s|^$/.test(src[from] || '')) return false;
    let end = from;
    while ((end = src.indexOf(close, end)) !== -1) {
      if (!escaped(src, end) && (close !== '$' || (!/\s/.test(src[end - 1]) && !/\d/.test(src[end + 1] || '')))) break;
      end += close.length;
    }
    if (end < 0 || end === from) return false;
    if (open === '$' && src.slice(from, end).includes('\n')) return false;
    if (!silent) {
      const token = state.push('note_math', '', 0);
      token.content = src.slice(from, end);
      token.meta = {display};
    }
    state.pos = end + close.length;
    return true;
  });
  md.block.ruler.before('fence', 'note_math_block', (state, line, endLine, silent) => {
    let start = state.bMarks[line] + state.tShift[line];
    const first = state.src.slice(start, state.eMarks[line]);
    const open = first.startsWith('$$') ? '$$' : first.startsWith('\\[') ? '\\[' : null;
    if (!open || state.sCount[line] - state.blkIndent >= 4) return false;
    const close = open === '$$' ? '$$' : '\\]';
    const from = start + open.length;
    let end = from;
    while ((end = state.src.indexOf(close, end)) !== -1 && escaped(state.src, end)) end += close.length;
    if (end < 0) return false;
    let last = line;
    while (last < endLine && state.eMarks[last] < end + close.length) last++;
    if (last >= endLine || state.src.slice(end + close.length, state.eMarks[last]).trim()) return false;
    if (silent) return true;
    const token = state.push('note_math_block', '', 0);
    token.block = true;
    token.map = [line, last + 1];
    token.content = state.src.slice(from, end).trim();
    state.line = last + 1;
    return true;
  }, {alt: ['paragraph', 'reference', 'blockquote', 'list']});
  md.renderer.rules.note_math = (tokens, idx) => render(tokens[idx].content, tokens[idx].meta.display);
  md.renderer.rules.note_math_block = (tokens, idx) => render(tokens[idx].content, true) + '\n';
}
