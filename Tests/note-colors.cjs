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
  assert(html.startsWith(`<h${level}>`),source);
  assert(html.includes('<strong>Тема</strong>') && html.includes('class="katex"'));
  assert(html.includes('note-topic') && !html.includes(marker+' Тема'));
 }
}
assert(md.render('абзац\n[# Заголовок]{topic}').includes('</p>\n<h1>'));
assert(md.render('- [# Заголовок]{topic}').includes('<li>\n<h1>'));
assert(md.render('> [## Заголовок]{definition}').includes('<h2>'));
assert(!md.render('```\n[# Пример кода]{topic}\n```').includes('<h1>'));
assert(!md.render('    [# Пример кода]{topic}').includes('<h1>'));
assert(!md.render('[# Неизвестный]{unknown}').includes('<h1>'));
console.log('PASS: colored headings h1–h6, existing wrapped headings, paragraphs, lists, quotes and literal code');
