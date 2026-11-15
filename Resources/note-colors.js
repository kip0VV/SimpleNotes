// Portable Markdown: [text]{topic}, [text]{text-orange}, [text]{bg-blue}.
// Only known styles are accepted; raw HTML stays disabled.
function noteColors(md) {
  const styles = new Set(['topic', 'definition', 'important', 'example',
    ...['orange','blue','green','yellow','pink','purple'].flatMap(c => ['text-'+c, 'bg-'+c])]);
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
