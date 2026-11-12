var lastClip='';async function clipPaste(){try{if(!$('autoclip').checked||$('urls').value.trim()||cur!=='links')return;var r=await api('clip',{});var x=((r&&r.text)||'').trim();
 if(!x||x===lastClip||!/^https?:\/\/\S+$/.test(x))return;lastClip=x;$('urls').value=x}catch(e){}}
addEventListener('focus',clipPaste);setTimeout(clipPaste,1500);
/* atalhos do teclado */
addEventListener('keydown',function(e){if(!(e.ctrlKey||e.metaKey))return;var k=e.key;
 if(k==='Enter'){e.preventDefault();go(cur==='links'&&P.items.length&&document.activeElement&&document.activeElement.closest&&document.activeElement.closest('#colR')?'pick':undefined)}
 else if(k==='l'||k==='L'){e.preventDefault();tab('links');$('urls').focus()}
 else if(k>='1'&&k<='4'){e.preventDefault();tab(['links','q','cfg','sup'][+k-1])}});
var _al=applyLang;applyLang=function(){_al.apply(this,arguments);renderQ();renderH()};
loadHist();renderQ();setTimeout(qLoad,800);
async function chk(){const u=opts().urls[0];if(!u)return;$('ck').textContent=t('ck_ing');await api('info',{url:u});
for(let i=0;i<90;i++){await new Promise(r=>setTimeout(r,700));const r=await api('infostate');if(!r.busy){$('ck').textContent=r.error?(t('ck_err')+r.error):(r.title+' · '+r.count+t('ck_cnt')+(r.ex?' · '+r.ex:''));return}}$('ck').textContent=t('ck_slow')}
var UPDX={},UPDGO=false;
$('updlater').onclick=function(){UPDX[$('updt').textContent.match(/[0-9]+(\.[0-9]+)+/)[0]]=1;$('updb').classList.add('hide')};
$('updgo').onclick=async function(){var r=await api('applyupd',{});if(r&&r.error){alert(r.error);return}UPDGO=true;$('updt').textContent=t('upd_restart');$('updgo').classList.add('hide');$('updlater').classList.add('hide')};
var CHKW=false;async function chkUpd(){UPDX={};UPDGO=false;CHKW=true;$('chkbtn').disabled=true;$('chkmsg').textContent=t('chk_run');await api('chkupd',{})}
function chkDone(s){if(!CHKW||!s.chk||s.chk==='run')return;CHKW=false;$('chkbtn').disabled=false;$('chkmsg').textContent=s.chk==='same'?t('chk_same').replace('{c}',s.appver||''):s.chk==='new'?t('chk_new').replace('{v}',s.updavail||''):t('chk_err')}
async function upd(){const r=await api('update',{});if(r.error)alert(r.error)}
async function shortcuts(){const r=await api('shortcut',{});alert(r.msg||r.error||'ok')}
/* ---- playlist tab ---- */
async function plLoad(){const u=$('plurl').value.trim();if(!u)return alert(t('pl_need'));P={items:[],from:0,busy:true,title:'',url:u};render();$('plinfo').textContent=t('pl_load');await api('pl/load',{url:u,browsers:common().browsers,nock:$('nock').checked});plPoll()}
async function plPoll(){try{const r=await api('pl?from='+P.from);const pm=radio('pm');
for(const it of r.items){it.checked=!it.unavail;it.type=pm==='v'?'v':'a';P.items.push(it)}P.from=r.total;P.title=r.title||P.title;P.busy=r.busy;P.err=r.err;render()
if(r.busy)setTimeout(plPoll,700);else if(!P.items.length&&r.err)$('plinfo').textContent=t('pl_fail')+r.err}catch(e){}}
