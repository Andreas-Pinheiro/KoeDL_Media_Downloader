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
document.querySelectorAll('input[name=kind]').forEach(e=>e.addEventListener('change',updFmt));updSafeBtn()}
// Modo cuidadoso: botao liga/desliga na tela de Configuracoes (o checkbox continua sendo a fonte do valor salvo).
function updSafeBtn(){const c=$('safe');if(!c)return;let b=$('safeBtn');
 if(!b){const w=document.createElement('div');w.id='safeCtl';w.style.cssText='display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:8px';
  b=document.createElement('button');b.type='button';b.id='safeBtn';
  b.addEventListener('click',()=>{c.checked=!c.checked;c.dispatchEvent(new Event('change',{bubbles:true}));updSafeBtn()});
  const i=document.createElement('button');i.type='button';i.id='safeInfo';i.textContent='i';
  i.style.cssText='width:28px;height:28px;padding:0;border-radius:50%;font-weight:700;flex:none';
  i.addEventListener('click',safeTip);
  w.appendChild(b);w.appendChild(i);
  const row=c.closest('label')||c.parentNode;c.style.display='none';row.insertAdjacentElement('afterend',w)}
 const on=!!c.checked;b.textContent=t(on?'safe_on':'safe_off');b.className=on?'':'s';b.setAttribute('aria-pressed',on?'true':'false');b.title=t('safe');
 const inf=$('safeInfo');if(inf){inf.title=t('safe_tip_t');inf.setAttribute('aria-label',t('safe_tip_t'));inf.className='s'}}
// Icone "i": popup com o custo do modo cuidadoso e o risco de desligar.
function safeTip(){if($('safeTip')){$('safeTip').remove();return}
 const ov=document.createElement('div');ov.id='safeTip';
 ov.style.cssText='position:fixed;inset:0;z-index:10000;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;padding:16px';
 const bx=document.createElement('div');bx.className='card';bx.setAttribute('role','dialog');bx.setAttribute('aria-modal','true');
 bx.style.cssText='max-width:540px;width:100%;max-height:82vh;overflow:auto';
 const h=document.createElement('h2');h.textContent=t('safe_tip_t');
 const p1=document.createElement('p');p1.textContent=t('safe_tip_b');
 const p2=document.createElement('p');p2.textContent=t('safe_tip_b2');
 const ok=document.createElement('button');ok.type='button';ok.className='s';ok.textContent=t('safe_tip_ok');
 ok.addEventListener('click',()=>ov.remove());
 bx.appendChild(h);bx.appendChild(p1);bx.appendChild(p2);bx.appendChild(ok);ov.appendChild(bx);
 ov.addEventListener('click',e=>{if(e.target===ov)ov.remove()});
 document.addEventListener('keydown',function esc(e){if(e.key==='Escape'){ov.remove();document.removeEventListener('keydown',esc)}});
 document.body.appendChild(ov);ok.focus()}
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
