/* Escolha da interface: Classica (a de sempre) ou Neon (a nova, com a personagem).
   A pagina em si vem montada do servidor (rota '/'), que olha o campo "ui" do settings.json;
   trocar aqui grava a escolha e recarrega. Este arquivo entra nas duas versoes da pagina,
   por isso da para voltar atras mesmo estando na interface nova. */
(function(){
 function txt(k){ return (typeof t==='function')?t(k):k }

 function montar(){
  var body=document.getElementById('cfgbody');
  if(!body || document.getElementById('skin')) return;

  var card=document.createElement('div');
  card.className='card';
  card.id='card_skin';

  // o menu das Configuracoes le o data-t do proprio <h2> de cada cartao
  var h=document.createElement('h2');
  h.setAttribute('data-t','h_skin');
  h.textContent=txt('h_skin');

  var lbl=document.createElement('label');
  lbl.className='fld';
  var ls=document.createElement('span');
  ls.setAttribute('data-t','skin_lbl');
  ls.textContent=txt('skin_lbl');
  var sel=document.createElement('select');
  sel.id='skin';
  var o1=document.createElement('option');o1.value='classic';o1.setAttribute('data-t','skin_classic');o1.textContent=txt('skin_classic');
  var o2=document.createElement('option');o2.value='neon';o2.setAttribute('data-t','skin_neon');o2.textContent=txt('skin_neon');
  sel.appendChild(o1);sel.appendChild(o2);
  lbl.appendChild(ls);lbl.appendChild(sel);

  var hint=document.createElement('div');
  hint.className='mu';
  hint.setAttribute('data-t','skin_hint');
  hint.textContent=txt('skin_hint');
  hint.style.marginTop='6px';

  card.appendChild(h);card.appendChild(lbl);card.appendChild(hint);
  body.insertBefore(card, body.firstChild);

  var atual=(document.body.getAttribute('data-ui')||'classic');
  sel.value=(atual==='neon')?'neon':'classic';

  function rotular(){
   card.querySelectorAll('[data-t]').forEach(function(n){ n.textContent=txt(n.dataset.t) });
  }
  rotular();
  var lsel=document.getElementById('lang');
  if(lsel) lsel.addEventListener('change',function(){ setTimeout(rotular,90) });

  var busy=false;
  sel.onchange=function(){
   if(busy) return; busy=true; sel.disabled=true;
   var v=(sel.value==='neon')?'neon':'classic';
   api('settings').then(function(s){ s=(s&&typeof s==='object')?s:{}; s.ui=v; return api('settings',s) })
    .then(function(){ location.reload() })
    .catch(function(){ busy=false; sel.disabled=false });
  };
  // o menu das Configuracoes pode ter sido montado antes deste cartao; avisa para refazer
  try{ if(typeof cfgNav==='function') cfgNav() }catch(e){}
 }

 if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',montar);
 else montar();
})();
