let LANG='en';
const t=k=>(D[LANG]&&D[LANG][k])||D.en[k]||k;
const api=(p,b)=>fetch('/api/'+p+(p.indexOf('?')<0?'?':'&')+'t='+T,b?{method:'POST',body:JSON.stringify(b)}:{}).then(r=>r.json());
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
let cur='links',P={items:[],from:0,busy:false,title:'',url:''},ready=false,running=false,lastStatus=null;
const IDS=['rate','frag','dirAudio','dirVideo','notif','after','autoclip','lookv','selfUpd','lang','openMode','theme','accent','fsize','density','corner','afmt','aq','vq','vcont','plmode','num','batch','splitType','st','en','noPl','nock','wait','meta','safe','reset','alt','addId','dlDir','chan','curmode','curpx2','curanim'];
const FS={s:12,m:14,l:16,xl:18};
function scl(){return Math.max(.85,Math.min(1.6,Math.min(innerWidth/1060,innerHeight/720)))}
window.addEventListener('resize',function(){try{applyLook()}catch(e){}});
function applyLook(){const h=document.documentElement,th=$('theme').value;
if(th==='auto')h.removeAttribute('data-theme');else h.setAttribute('data-theme',th);
h.style.fontSize=((FS[$('fsize').value]||14)*scl())+'px';
if($('density').value==='compact')h.setAttribute('data-dens','compact');else h.removeAttribute('data-dens');
applyCursor();if($('corner').value==='square')h.setAttribute('data-corner','square');else h.removeAttribute('data-corner');
const c=$('accent').value||'#7c3aed';h.style.setProperty('--ac',c);
const n=parseInt(c.slice(1),16),r=n>>16,g=(n>>8)&255,b=n&255,L=(0.299*r+0.587*g+0.114*b);h.style.setProperty('--acfg',L>150?'#111':'#fff');
document.querySelectorAll('#sw button[data-c]').forEach(x=>{x.style.background=x.dataset.c;x.classList.toggle('on',x.dataset.c.toLowerCase()===c.toLowerCase())})}
function resetLook(){$('theme').value='neon';$('fsize').value='m';$('density').value='compact';$('corner').value='round';$('curmode').value='pack';$('curpx2').value='32';$('curanim').value='full';$('accent').value='#7c3aed';applyLook();save()}
document.querySelectorAll('#sw button[data-c]').forEach(x=>x.addEventListener('click',()=>{$('accent').value=x.dataset.c;applyLook();save()}));
function radio(n){const e=document.querySelector('input[name='+n+']:checked');return e?e.value:''}
function setRadio(n,v){document.querySelectorAll('input[name='+n+']').forEach(e=>e.checked=e.value===v)}
function updFmt(){const k=radio('kind'),pm=radio('pm');
const a=k==='a'||pm!=='v',v=k==='v'||pm!=='a';
$('gA').classList.toggle('hide',!a);$('gV').classList.toggle('hide',!v);
}

function cfgNav(){var nav=$('cfgnav'),cards=[].slice.call(document.querySelectorAll('#cfgbody>.card'));nav.innerHTML='';
 cards.forEach(function(c,i){var key=c.querySelector('h2').dataset.t,b=document.createElement('button');if(key==='h_where')key='n_where';if(key==='h_acc')key='n_acc';b.dataset.t=key;b.textContent=t(key);
  b.onclick=function(){cards.forEach(function(x,j){x.classList.toggle('on',j===i)});[].forEach.call(nav.children,function(x,j){x.classList.toggle('on',j===i)});try{sessionStorage.setItem('cfgsec',i)}catch(e){}};nav.appendChild(b)});
 var k=0;try{k=+sessionStorage.getItem('cfgsec')||0}catch(e){} if(k>=cards.length)k=0;nav.children[k].click()}
function applyLang(){document.documentElement.lang=LANG;
document.querySelectorAll('[data-t]').forEach(e=>e.textContent=t(e.dataset.t));
document.querySelectorAll('[data-ph]').forEach(e=>e.placeholder=t(e.dataset.ph));
$('go').textContent=t('go');updGop();
if(P.items.length){render()}else if(!P.busy){$('plinfo').textContent=t('plhint')}
if(lastStatus)showStatus(lastStatus)}
