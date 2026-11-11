// Ranges highlight rendered text without rewriting the DOM or touching math markup.
window.findInNote = (query, requestedIndex, scroll) => {
  if (window.CSS && CSS.highlights) {
    CSS.highlights.delete('note-matches');
    CSS.highlights.delete('note-current');
  }
  const nodes = [];
  const walker = document.createTreeWalker(document.getElementById('body'), NodeFilter.SHOW_TEXT, {
    acceptNode: node => node.parentElement.closest('.katex-mathml,script,style') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
  });
  let node, text = '', previousBlock = null;
  while ((node = walker.nextNode())) {
    const block = node.parentElement.closest('p,h1,h2,h3,h4,h5,h6,li,pre,td,th,blockquote,.katex-display');
    if (previousBlock && block !== previousBlock) text += '\n';
    previousBlock = block;
    nodes.push({node, start:text.length, end:text.length+node.textContent.length});
    text += node.textContent;
  }
  const ranges = [];
  const words = query.trim().split(/\s+/u).filter(Boolean);
  if (!words.length) {
    window.getSelection().removeAllRanges();
    return {count:0,index:0};
  }
  if (words.length) {
    const escaped = words.map(word => word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('\\s+');
    let firstIndex = 0, lastIndex = 0;
    for (const match of text.matchAll(new RegExp(escaped, 'giu'))) {
      const found = match.index, end = found + match[0].length;
      while (firstIndex < nodes.length && nodes[firstIndex].end <= found) firstIndex++;
      while (lastIndex < nodes.length && nodes[lastIndex].end < end) lastIndex++;
      const first = nodes[firstIndex], last = nodes[lastIndex];
      if (first && last && first.start <= found && last.start < end) {
        const range = document.createRange();
        range.setStart(first.node, found-first.start);
        range.setEnd(last.node, end-last.start);
        ranges.push(range);
      }
    }
  }
  const count = ranges.length, index = count ? ((requestedIndex % count)+count)%count : 0;
  if (window.CSS && CSS.highlights && window.Highlight) {
    const all = new Highlight();
    ranges.forEach(range => all.add(range));
    CSS.highlights.set('note-matches', all);
    if (count) CSS.highlights.set('note-current', new Highlight(ranges[index]));
  } else if (scroll || !query.trim()) {
    const selection = window.getSelection();
    selection.removeAllRanges();
    if (count) selection.addRange(ranges[index]);
  }
  if (scroll && count) {
    const rect = ranges[index].getBoundingClientRect();
    window.scrollBy({top:rect.top-window.innerHeight/2, behavior:'instant'});
  }
  return {count,index};
};
