function tab(k){cur=k;document.body.dataset.tab=k;for(const x of['links','q','lib','cfg','sup']){$('p_'+x).classList.toggle('on',x===k);$('t_'+x).classList.toggle('on',x===k)}
if(k==='lib')libLoad();updFmt()}
function common(){const o={};for(const i of IDS){const e=$(i);o[i]=e.type==='checkbox'?e.checked:e.value}
o.browsers=[...document.querySelectorAll('.br:checked')].map(e=>e.value);o.kind=radio('kind');o.pm=radio('pm');o.plurl=$('plurl').value;return o}
let sv=null;function save(){clearTimeout(sv);sv=setTimeout(()=>api('settings',common()),400)}
async function load(){try{const s=await api('settings');for(const i of IDS){if(!(i in s))continue;const e=$(i);if(e.type==='checkbox')e.checked=!!s[i];else e.value=s[i]}
if(s.browsers)document.querySelectorAll('.br').forEach(e=>e.checked=s.browsers.indexOf(e.value)>=0);if(s.kind)setRadio('kind',s.kind);if(s.pm)setRadio('pm',s.pm);if(s.plurl)$('plurl').value=s.plurl}catch(e){}
if($('lookv').value!=='3'){$('theme').value='neon';$('density').value='compact';$('curanim').value='full';$('accent').value='#7c3aed';$('lookv').value='3';save()}
LANG=$('lang').value||'en';if(!D[LANG])LANG='en';$('lang').value=LANG;applyLook();cfgNav();applyLang();updFmt();
document.querySelectorAll('input,select').forEach(e=>{e.addEventListener('change',save);if(e.type==='color')e.addEventListener('input',()=>{applyLook();save()})});
['theme','fsize','density','corner','curmode','curpx2','curanim'].forEach(i=>$(i).addEventListener('change',applyLook));
$('lang').addEventListener('change',()=>{LANG=$('lang').value;applyLang();save()});
document.querySelectorAll('input[name=kind]').forEach(e=>e.addEventListener('change',updFmt))}
function opts(){const o=common();o.urls=$('urls').value.split('\n').map(s=>s.trim()).filter(s=>s&&s[0]!=='#');return o}
function updGop(){const n=P.items.filter(x=>x.checked&&!x.unavail).length;$('gop').textContent=t('go_pick')+(n?' ('+n+')':'');$('gop').classList.toggle('hide',!P.items.length)}
async function go(m){let o,label,kind='a';
 if(m==='pick'){const sel=P.items.filter(x=>x.checked&&!x.unavail);if(!sel.length)return alert(t('a_pick'));
  o=common();o.mode='pick';o.plUrl=P.url||$('plurl').value;o.plTitle=P.title;o.maxIdx=Math.max.apply(null,P.items.map(x=>x.idx||0).concat([P.items.length]));
  o.items=sel.map(x=>({idx:x.idx,title:x.title,url:x.url,type:x.type}));label=(P.title||'Playlist')+' · '+sel.length;kind=sel.every(x=>x.type==='v')?'v':'a'}
 else{o=opts();o.mode='links';if(!o.urls.length){$('urls').focus();return alert(t('a_links'))}
  label=o.urls[0].replace(/^https?:\/\/(www\.)?/,'').slice(0,60)+(o.urls.length>1?' +'+(o.urls.length-1):'');kind=o.kind==='v'?'v':'a';$('urls').value=''}
 enqueue(o,label,kind)}
/* ---- fila, historico e extras ---- */
