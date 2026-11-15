const fs = require('fs'), vm = require('vm'), assert = require('assert');
const ctx = {}; ctx.window = ctx; vm.createContext(ctx);
for (const file of ['markdown-it.min.js','katex.js','markdown-math.js','note-colors.js']) vm.runInContext(fs.readFileSync('Resources/'+file,'utf8'),ctx);
const md=ctx.markdownit({html:false,breaks:true}).use(ctx.noteMath).use(ctx.noteColors);
for(const style of ['topic','definition','important','example',...['orange','blue','green','yellow','pink','purple'].flatMap(c=>['text-'+c,'bg-'+c])]) {
 assert(md.render(`[Слово]{${style}}`).includes(`class="note-color note-${style}"`));
}
let html=md.render('[**Тема** и $x^2$]{topic} [[два]{text-orange}]{bg-blue} [обычная ссылка](https://example.com)');
assert(html.includes('<strong>Тема</strong>') && html.includes('class="katex"'));
assert(html.includes('note-text-orange') && html.includes('note-bg-blue') && html.includes('href="https://example.com"'));
for(const source of ['`[код]{topic}`','```\n[код]{topic}\n```','\\[текст]{topic}','[текст]{unknown}','[текст]{text-red;onclick=evil}']) assert(!md.render(source).includes('class="note-color'),source);
assert(md.render('[<script>alert(1)</script>]{topic}').includes('&lt;script&gt;'));
assert(md.render('[первая\nвторая]{definition}').includes('<br>'));
assert(md.render('[текст с [скобками]]{topic}').includes('note-topic'));
assert(md.render('[нет закрытия]{topic').includes('{topic'));
console.log('PASS: all color styles, nesting, Markdown/math, multiline, code, escapes and unsafe input');

// Whole-heading colors must retain Markdown block structure, including old saved markup.
for (let level=1;level<=6;level++) {
 const marker='#'.repeat(level);
 for(const source of [`[${marker} **Тема** и $x^2$]{topic}`, `${marker} [**Тема** и $x^2$]{topic}`]) {
  const html=md.render(source);
  assert(html.startsWith(`<h${level} id="`),source);
  assert(html.includes('<strong>Тема</strong>') && html.includes('class="katex"'));
  assert(html.includes('note-topic') && !html.includes(marker+' Тема'));
 }
}
assert(md.render('абзац\n[# Заголовок]{topic}').includes('</p>\n<h1 id='));
assert(md.render('- [# Заголовок]{topic}').includes('<li>\n<h1 id='));
assert(md.render('> [## Заголовок]{definition}').includes('<h2 id='));
assert(!md.render('```\n[# Пример кода]{topic}\n```').includes('<h1>'));
assert(!md.render('    [# Пример кода]{topic}').includes('<h1>'));
assert(!md.render('[# Неизвестный]{unknown}').includes('<h1>'));
console.log('PASS: colored headings h1–h6, existing wrapped headings, paragraphs, lists, quotes and literal code');

for(const [source, tag] of [['[*курсив*]{topic}','em'],['[`код`]{topic}','code'],['[[ссылка](https://example.com)]{text-orange}','a'],['- [пункт]{topic}','li'],['1. [пункт]{topic}','li'],['> [цитата]{topic}','blockquote'],['| A |\n|---|\n| [ячейка]{topic} |','td']]) { const html=md.render(source); assert(html.includes('<'+tag),source);assert(html.includes('note-color'),source); }
console.log('PASS: colored italic, inline code, links, lists, quotes and table cells');

const transform = (text,style,a=0,b=text.length)=>ctx.transformNoteColor(text,a,b-a,style);
for(const source of ['- One\n- Two','> ## Heading\n> Text','- [ ] Task']) assert(transform(source,'topic').error);
assert.strictEqual(transform('`[code]{topic}` and [word]{topic}','clear').text,'`[code]{topic}` and word');
assert.strictEqual(transform('> ```\n> [code]{topic}\n> ```','clear').text,'> ```\n> [code]{topic}\n> ```');
assert(transform('> ```\n> code\n> ```','topic').error);
assert.strictEqual(transform('[important word]{topic}','clear',11,15).text,'important word');
assert.strictEqual(transform('[**bold** and word]{topic}','clear',13,17).text,'**bold** and word');
assert.strictEqual(transform('[Term]{topic}','definition',1,5).text,'[Term]{definition}');
assert(md.render('# [Тема]{topic}\n\n# Тема').includes('id="тема-1"'));
console.log('PASS: parser-aware source edits, nested quoted fences, partial clearing and unique Unicode heading IDs');

assert(transform('**bold**','topic',0,4).error, 'Crossed emphasis boundary must not damage Markdown');
assert(transform('$x^2$','topic',1,4).error, 'Partial formulas are protected');
assert.strictEqual(transform('**bold**','topic').text,'[**bold**]{topic}');
assert.strictEqual(transform('***both***','topic').text,'[***both***]{topic}');
assert.strictEqual(transform('*italic*','topic').text,'[*italic*]{topic}');
assert.strictEqual(transform('## *Heading*','topic').text,'## [*Heading*]{topic}');

assert.strictEqual(transform('[# **Heading**]{topic}','clear',6,10).text,'# **Heading**');

for(const source of ['| A | B |\n|---|---|\n| cell | cell |','| A | B |\n|—|—|\n| C | 0 |','$x^2$','`code`','[link](https://example.com)','~~strike~~','![alt](x)']) {
 const result=transform(source,'topic');
 assert(result.error && result.text===undefined,source);
}
const table='| [A]{topic} | [B]{topic} |\n|---|---|\n| C | 0 |';
assert.strictEqual(transform(table,'clear').text,'| A | B |\n|---|---|\n| C | 0 |');
console.log('PASS: restrictive color policy, malformed tables, whole formulas/code, and table color recovery');

const headingEdit=transform('## *Heading*','topic');
assert.strictEqual(headingEdit.text.slice(headingEdit.start,headingEdit.start+headingEdit.length),'*Heading*');
