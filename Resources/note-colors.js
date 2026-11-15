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
  md.core.ruler.after('inline', 'note_heading_ids', state => {
    const used = new Set(['title','date','body']);
    state.tokens.forEach((token,i) => {
      if(token.type !== 'heading_open') return;
      const inline = state.tokens[i+1];
      const text = (inline.children || []).filter(t=>t.nesting===0).map(t=>t.content).join('');
      const base = text.toLowerCase().normalize('NFC').replace(/[^\p{L}\p{N}_\s-]/gu,'').trim().replace(/\s+/g,'-') || 'section';
      let id=base, n=1; while(used.has(id)) id=base+'-'+n++;
      used.add(id); token.attrSet('id',id);
    });
  });
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

// Source transformations use the same block and inline rules as the preview.
// Positions are UTF-16 offsets, shared by JavaScript and NSTextView.
function transformNoteColor(source, start, length, style) {
  const md = markdownit({html:false}).use(noteColors);
  if (typeof noteMath === 'function') md.use(noteMath);
  const lines = source.split('\n'), offsets = [];
  let offset = 0;
  for (const line of lines) { offsets.push(offset); offset += line.length + 1; }
  offsets.push(source.length);
  const spans = [], colors = [], code = [];
  let map = null;
  for (const name of ['note_color', 'backticks', ...(typeof noteMath === 'function' ? ['note_math'] : [])]) {
    const rule = md.inline.ruler.__rules__.find(r => r.name === name);
    const original = rule.fn;
    rule.fn = (state, silent) => {
      const begin = state.pos;
      const ok = original(state, silent);
      if (ok && !silent && map) {
        const a = map(begin), b = map(state.pos);
        if (a != null && b != null) {
          if (name === 'note_color') {
            const tail = /\]\{([a-z-]+)\}$/.exec(state.src.slice(begin,state.pos));
            if (tail) colors.push({a,b,innerA:a+1,innerB:b-tail[0].length,style:tail[1]});
          } else if (name === 'note_math') code.push({a,b});
          else if (state.src[begin] === '`' && state.src.slice(begin,state.pos).includes('`',1)) code.push({a,b});
        }
      }
      return ok;
    };
  }
  md.core.ruler.at('inline', state => {
    let rowMap=null, rowCursor=0;
    for (const token of state.tokens) {
      if(token.type==='tr_open') { rowMap=token.map; rowCursor=0; }
      if(token.type==='tr_close') rowMap=null;
      if (token.type !== 'inline') continue;
      const tokenMap=token.map || rowMap;
      if(!tokenMap) { state.md.inline.parse(token.content,state.md,state.env,token.children); continue; }
      const contentLines = token.content.split('\n'), positions = [];
      let valid = true, n = 0;
      for (let j=0;j<contentLines.length;j++) {
        const line = lines[tokenMap[0]+j] || '';
        let at = token.map ? line.lastIndexOf(contentLines[j]) : line.indexOf(contentLines[j],rowCursor);
        if(at>=0 && !token.map) rowCursor=at+contentLines[j].length;
        if(at<0 && j===0) {
          const legacy = /\[(#{1,6})[ \t]+/.exec(line);
          if(legacy && line.slice(legacy.index).replace(/^\[(#{1,6})[ \t]+/,'[').trimEnd()===contentLines[j]) {
            const skip=legacy[0].length-1;
            for(let k=0;k<=contentLines[j].length;k++) positions[n+k]=offsets[tokenMap[0]]+legacy.index+k+(k?skip:0);
            spans.push({a:positions[n],b:positions[n+contentLines[j].length]});
            n+=contentLines[j].length+1;
            continue;
          }
        }
        if (at < 0) { valid=false; break; }
        for(let k=0;k<=contentLines[j].length;k++) positions[n+k] = offsets[tokenMap[0]+j]+at+k;
        if(contentLines[j].length) {
          const task = /(?:[-+*]|[0-9]+[.)])\s+$/.test(line.slice(0,at)) && /^\[[ xX]\]\s+/.exec(contentLines[j]);
          spans.push({a:positions[n]+(task?task[0].length:0),b:positions[n+contentLines[j].length]});
        }
        n += contentLines[j].length + 1;
      }
      map = valid ? p => positions[p] : null;
      state.md.inline.parse(token.content,state.md,state.env,token.children);
      map = null;
    }
  });
  const tokens = md.parse(source,{});
  const blocked = tokens.filter(t => ['fence','code_block','html_block','note_math_block'].includes(t.type) && t.map)
    .map(t => ({a:offsets[t.map[0]],b:offsets[t.map[1]]}));
  const end = start + length, overlaps = r => r.a < end && r.b > start;
  const edits = [];
  if (style === 'clear') {
    // Clear enclosing annotations as a unit: splitting one through **emphasis**,
    // links or math would damage the original Markdown structure.
    for (const color of colors.filter(overlaps)) {
      edits.push({a:color.a,b:color.innerA,text:''},{a:color.innerB,b:color.b,text:''});
    }
  } else {
    if (blocked.some(overlaps) || code.some(r => overlaps(r) && !(start <= r.a && end >= r.b)))
      return {error:'Выдели обычный текст или код вместе с обратными кавычками. Блоки кода не раскрашиваются.'};
    const kind = s => s.startsWith('text-') ? 'text' : s.startsWith('bg-') ? 'bg' : 'semantic';
    const replaced = colors.filter(c => c.innerA === start && c.innerB === end && kind(c.style) === kind(style));
    for(const c of replaced) edits.push({a:c.a,b:c.innerA,text:''},{a:c.innerB,b:c.b,text:''});
    const targets = spans.map(r => ({a:Math.max(start,r.a),b:Math.min(end,r.b)})).filter(r => r.a<r.b);
    if(!targets.length) return {error:'В этом фрагменте нет обычного текста для раскрашивания.'};
    // Reject crossing a pre-existing annotation boundary, rather than emit
    // unbalanced brackets. Whole annotations and nested selections are safe.
    if(colors.some(c => targets.some(r => (r.a>c.a && r.a<c.innerA && r.b<c.b) || (r.a>c.innerA && r.a<c.b && r.b>=c.b))))
      return {error:'Выдели слова внутри одного цветового фрагмента или весь фрагмент целиком.'};
    for(const r of targets) edits.push({a:r.b,b:r.b,text:']{'+style+'}'},{a:r.a,b:r.a,text:'['});
  }
  if(!edits.length) return {text:source,start,length};
  // Deletions at an insertion point must run first; all positions refer to source.
  edits.sort((x,y) => y.a-x.a || (y.b-y.a)-(x.b-x.a));
  let text=source;
  for(const e of edits) text=text.slice(0,e.a)+e.text+text.slice(e.b);
  const verify = markdownit({html:false}).use(noteColors);
  if(typeof noteMath === 'function') verify.use(noteMath);
  const signature = tokens => {
    const result=[];
    for(const t of tokens) {
      if(t.type==='note_color_open'||t.type==='note_color_close') continue;
      const item = {type:t.type,tag:t.tag,nesting:t.nesting};
      if(t.type==='inline') item.children=signature(t.children||[]);
      else item.content=t.content;
      if(t.attrs) item.attrs=t.attrs;
      const last=result[result.length-1];
      if(t.type==='text' && last && last.type==='text') last.content+=t.content;
      else result.push(item);
    }
    return result;
  };
  if(JSON.stringify(signature(verify.parse(source,{}))) !== JSON.stringify(signature(verify.parse(text,{}))))
    return {error:'Такое выделение разрывает Markdown-разметку. Выдели слова внутри форматирования или фрагмент вместе со всеми его маркерами.'};
  const before = edits.filter(e => e.b<=start && e.a<start).reduce((n,e)=>n+e.text.length-(e.b-e.a),0);
  const selected = Math.max(0, length + edits.filter(e=>e.a>=start && e.b<=end).reduce((n,e)=>n+e.text.length-(e.b-e.a),0));
  // Preserve the ordinary single-fragment selection for applying another style.
  const single = style!=='clear' && !source.slice(start,end).includes('\n');
  return {text,start:start+before+(single?1:0),length:single?length:Math.min(selected,text.length-start-before)};
}
