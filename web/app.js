const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ESCAPES[c]);
const safeIcon = (icon) => String(icon || 'fa-solid fa-circle-dot').replace(/[^\w\s-]/g, '');
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'arca_target';
const post = (name, data = {}) =>
    fetch(`https://${resource}/${name}`, { method: 'POST', body: JSON.stringify(data) }).catch(() => {});

const target = document.getElementById('target');
const eye = document.getElementById('eye');
const list = document.getElementById('options');

function setOptions(options) {
    eye.classList.toggle('has-options', options.length > 0);
    list.innerHTML = '';
    options.forEach((opt, i) => {
        const el = document.createElement('button');
        el.className = 'option';
        el.innerHTML = `<i class="${safeIcon(opt.icon)}"></i><span>${esc(opt.label)}</span>`;
        el.addEventListener('click', () => post('select', { index: i + 1 }));
        list.appendChild(el);
    });
}

window.addEventListener('message', ({ data }) => {
    switch (data.action) {
        case 'show': target.classList.remove('hidden'); setOptions([]); break;
        case 'hide': target.classList.add('hidden'); setOptions([]); break;
        case 'options': setOptions(data.data); break;
    }
});

window.addEventListener('keydown', (e) => { if (e.key === 'Escape' || e.key === 'Alt') post('close'); });
window.addEventListener('contextmenu', (e) => { e.preventDefault(); post('close'); });
window.addEventListener('mousedown', (e) => { if (e.target === document.body) post('close'); });
