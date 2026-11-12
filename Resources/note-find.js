// Highlight text fragments with ordinary spans; WebKit CSS Highlight painting can go stale.
window.findInNote = (query, requestedIndex, scroll) => {
  if (window.CSS && CSS.highlights) {
    CSS.highlights.delete('note-matches');
    CSS.highlights.delete('note-current');
  }
  document.querySelectorAll('[data-note-find]').forEach(mark => {
    const parent = mark.parentNode;
    mark.replaceWith(...mark.childNodes);
    parent.normalize();
  });
  if (!query.trim()) {
    window.getSelection()?.removeAllRanges();
    return {count:0,index:0};
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
  // Work backwards so splitting a text node cannot invalidate later offsets.
  let currentMark = null;
  const fragments = [];
  ranges.forEach((range, matchIndex) => {
    for (const entry of nodes) {
      if (!range.intersectsNode(entry.node)) continue;
      const start = entry.node === range.startContainer ? range.startOffset : 0;
      const end = entry.node === range.endContainer ? range.endOffset : entry.node.length;
      if (end > start) fragments.push({node:entry.node,start,end,matchIndex});
    }
  });
  for (const fragment of fragments.reverse()) {
    const range = document.createRange();
    range.setStart(fragment.node, fragment.start);
    range.setEnd(fragment.node, fragment.end);
    const mark = document.createElement('span');
    mark.dataset.noteFind = String(fragment.matchIndex);
    mark.style.backgroundColor = fragment.matchIndex === index ? 'rgba(255,150,35,.65)' : 'rgba(255,215,0,.35)';
    range.surroundContents(mark);
    if (fragment.matchIndex === index) currentMark = mark;
  }
  if (scroll && currentMark) {
    const rect = currentMark.getBoundingClientRect();
    const root = document.scrollingElement;
    const target = root.scrollTop + rect.top - window.innerHeight / 2;
    root.scrollTop = Math.max(0, Math.min(target, root.scrollHeight - root.clientHeight));
  }
  return {count,index};
};
