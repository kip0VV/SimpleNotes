// Portable Markdown: [text]{topic}, [text]{text-orange}, [text]{bg-blue}.
// Only known styles are accepted; raw HTML stays disabled.
function noteColors(md) {
  const styles = new Set(['topic', 'definition', 'important', 'example',
    ...['orange','blue','green','yellow','pink','purple'].flatMap(c => ['text-'+c, 'bg-'+c])]);
  // Older notes may wrap the heading marker itself: [# Heading]{topic}.
  // Recover the block structure without enabling HTML or touching source files.
  md.block.ruler.before('heading', 'note_color_heading', (state, line, endLine, silent) => {
    if (state.sCount[line] - state.blkIndent >= 4) return false;
    const start = state.bMarks[line] + state.tShift[line];
    const text = state.src.slice(start, state.eMarks[line]);
    const match = /^\[(#{1,6})[ \t]+(.+)\]\{([a-z-]+)\}[ \t]*$/.exec(text);
    if (!match || !styles.has(match[3])) return false;
    if (silent) return true;
    const tag = 'h' + match[1].length;
    const open = state.push('heading_open', tag, 1);
    open.markup = match[1]; open.map = [line, line + 1];
    const inline = state.push('inline', '', 0);
    inline.content = '[' + match[2].replace(/[ \t]+#+[ \t]*$/, '') + ']{' + match[3] + '}';
    inline.map = [line, line + 1]; inline.children = [];
    const close = state.push('heading_close', tag, -1); close.markup = match[1];
    state.line = line + 1;
    return true;
  }, {alt: ['paragraph', 'reference', 'blockquote']});
  md.inline.ruler.before('link', 'note_color', (state, silent) => {
    if (state.src[state.pos] !== '[') return false;
    const start = state.pos;
    const end = md.helpers.parseLinkLabel(state, start, false);
    if (end < 0) return false;
    const match = /^\{([a-z-]+)\}/.exec(state.src.slice(end + 1, state.posMax));
    if (!match || !styles.has(match[1]) || end === start + 1) return false;
    const finish = end + 1 + match[0].length;
    if (!silent) {
      const max = state.posMax;
      state.push('note_color_open', 'span', 1).attrs = [['class', 'note-color note-'+match[1]]];
      state.pos = start + 1;
      state.posMax = end;
      state.md.inline.tokenize(state);
      state.push('note_color_close', 'span', -1);
      state.posMax = max;
    }
    state.pos = finish;
    return true;
  });
}
