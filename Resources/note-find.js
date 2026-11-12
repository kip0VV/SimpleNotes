// Highlight text fragments safely without breaking the DOM structure.
window.findInNote = (query, requestedIndex, scroll) => {
  // 1. Очищаем предыдущие результаты поиска
  if (window.CSS && CSS.highlights) {
    CSS.highlights.delete('note-matches');
    CSS.highlights.delete('note-current');
  }
  document.querySelectorAll('[data-note-find]').forEach(mark => {
    const parent = mark.parentNode;
    if (parent) {
      mark.replaceWith(...mark.childNodes);
      parent.normalize();
    }
  });
  window.getSelection()?.removeAllRanges();

  if (!query.trim()) return {count:0,index:0};

  const body = document.getElementById('body');
  if (!body) return {count:0,index:0};

  // 2. Собираем текстовые узлы
  const nodes = [];
  const walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, {
    acceptNode: node => {
      // Пропускаем скрипты, стили и математические формулы KaTeX
      if (node.parentElement && node.parentElement.closest('.katex-mathml,script,style')) {
        return NodeFilter.FILTER_REJECT;
      }
      return NodeFilter.FILTER_ACCEPT;
    }
  });

  let node, text = '', previousBlock = null;
  while ((node = walker.nextNode())) {
    const block = node.parentElement.closest('p,h1,h2,h3,h4,h5,h6,li,pre,td,th,blockquote,.katex-display');
    if (previousBlock && block !== previousBlock) text += '\n';
    previousBlock = block;
    nodes.push({node, start:text.length, end:text.length+node.textContent.length});
    text += node.textContent;
  }

  // 3. Ищем совпадения
  const ranges = [];
  const words = query.trim().split(/\s+/u).filter(Boolean);
  if (!words.length) return {count:0,index:0};

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

  const count = ranges.length;
  const index = count ? ((requestedIndex % count)+count)%count : 0;
  let currentMark = null;

  // 4. Подсветка
  // Если браузер поддерживает CSS Custom Highlight API (macOS 12.3+), используем его (самый безопасный способ)
  if (window.CSS && CSS.highlights) {
    const matchesHighlight = new Highlight();
    const currentHighlight = new Highlight();
    ranges.forEach((range, i) => {
      if (i === index) currentHighlight.add(range);
      else matchesHighlight.add(range);
    });
    CSS.highlights.set('note-matches', matchesHighlight);
    CSS.highlights.set('note-current', currentHighlight);
    
    // Для скролла нам все равно нужен элемент, поэтому используем Range
    if (scroll && ranges[index]) {
      const rect = ranges[index].getBoundingClientRect();
      const root = document.scrollingElement;
      const target = root.scrollTop + rect.top - window.innerHeight / 2;
      root.scrollTop = Math.max(0, Math.min(target, root.scrollHeight - root.clientHeight));
    }
    return {count, index};
  } 
  
  // Фоллбэк для старых версий: аккуратно оборачиваем в span
  for (const range of [...ranges].reverse()) {
    const mark = document.createElement('span');
    mark.dataset.noteFind = String(ranges.indexOf(range));
    mark.style.backgroundColor = mark.dataset.noteFind == index ? 'rgba(255,150,35,.65)' : 'rgba(255,215,0,.35)';
    
    // Вместо surroundContents (который падает) извлекаем и вставляем содержимое
    const fragment = range.extractContents();
    mark.appendChild(fragment);
    range.insertNode(mark);
    
    if (mark.dataset.noteFind == index) currentMark = mark;
  }

  if (scroll && currentMark) {
    const rect = currentMark.getBoundingClientRect();
    const root = document.scrollingElement;
    const target = root.scrollTop + rect.top - window.innerHeight / 2;
    root.scrollTop = Math.max(0, Math.min(target, root.scrollHeight - root.clientHeight));
  }

  return {count,index};
};