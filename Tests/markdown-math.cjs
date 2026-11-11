const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const root = path.join(__dirname, '..');
const context = vm.createContext({window: {}});
for (const file of ['markdown-it.min.js', 'katex.js', 'markdown-math.js']) {
  vm.runInContext(fs.readFileSync(path.join(root, 'Resources', file), 'utf8'), context);
}
context.katex = context.window.katex;
const md = vm.runInContext('markdownit({html:false,breaks:true}).use(noteMath)', context);
const example = '# Условие\n\n$$\nx(t)=\\tan^2 t, \\qquad y(t)=\\ln(\\cos t).\n$$\n\nНайти производную $y$ по $x$, то есть $\\dfrac{dy}{dx}$.\n\nЗдесь $\\tan t$ — тангенс, то же самое, что $\\operatorname{tg}t$.';
const html = md.render(example);
assert.equal((html.match(/class="katex"/g) || []).length, 6);
assert(html.includes('katex-display'));
assert(!html.includes('math-error'));
for (const source of ['$x_i^2 + y_j$', '\\(\\frac{a}{b}\\)', '\\[x^2\n+y^2\\]', '$$x^2$$', '- $a_1$\n- $b_2$']) {
  assert(md.render(source).includes('class="katex"'), source);
}
for (const source of ['`$x$`', '```latex\n$$x$$\n```', '\\$x\\$', 'Цена $5 и $10', 'текст $без закрытия']) {
  assert(!md.render(source).includes('class="katex"'), source);
}
assert(md.render('$\\unknowncommand{x}$\n\n**Дальше**').includes('math-error'));
assert(md.render('$\\unknowncommand{x}$\n\n**Дальше**').includes('<strong>Дальше</strong>'));
assert(!md.render('$\\href{javascript:alert(1)}{x}$').includes('href="javascript:'));
assert(md.render('- [ ] задача\n\n$$x$$\n\n- [x] готово').includes('katex-display'));
console.log('PASS: sample formulas, delimiters, indices, code, escapes, prices, malformed and unsafe TeX');
