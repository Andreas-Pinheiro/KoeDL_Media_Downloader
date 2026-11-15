/* Interface nova: personagem lateral, estado vazio (dormindo), chips da barra, indicador online */
$('sideimg').src='data:image/webp;base64,@@B64:assets/ui/lado.webp@@';
const SLEEP='data:image/webp;base64,@@B64:assets/ui/dorme.webp@@';
(function(){
 var tw=document.querySelector('#p_links .tw');if(!tw)return;
 var e=document.createElement('div');e.id='empty';
 e.innerHTML='<div class="zimg"><img alt="" src="'+SLEEP+'"><i class="zz z1">z</i><i class="zz z2">z</i><i class="zz z3">Z</i></div><b data-t="empty_t"></b><span class="el"><u></u><span data-t="empty_s"></span><u></u></span>';
 tw.appendChild(e);
 e.querySelectorAll('[data-t]').forEach(function(n){n.textContent=t(n.dataset.t)});
 function onl(ok){var o=$('onl');if(o){o.className=ok?'on':'off';$('onlt').textContent=t(ok?'onl':'offl')}}
 function sync(){onl($('stline').textContent!==t('closed'));var none=!(P&&P.items&&P.items.length)&&!(P&&P.busy);e.classList.toggle('on',none);
  var pi=$('plinfo');pi.classList.toggle('hide',none&&pi.textContent===t('plhint'))}
 var _r=render;render=function(){_r.apply(this,arguments);sync()};
 var _s=showStatus;showStatus=function(s){_s.apply(this,arguments);
  $('bspd').textContent=(s.running&&s.speed)?s.speed:'0 B/s';$('beta').textContent=(s.running&&s.eta)?s.eta:'--:--';sync()};
 setInterval(sync,1000);sync();
})();
