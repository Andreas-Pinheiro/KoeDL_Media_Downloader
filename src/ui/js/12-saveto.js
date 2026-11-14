/* "Salvar em": escolher a pasta de musicas e de videos na propria tela de download.
   Os campos espelham dirAudio/dirVideo (Configuracoes), entao tudo continua salvo no mesmo lugar. */
(function(){
 var MAP=[['stA','dirAudio','stAb'],['stV','dirVideo','stVb']];
 function pull(){MAP.forEach(function(m){var a=$(m[0]),b=$(m[1]);if(a&&b&&document.activeElement!==a&&a.value!==b.value)a.value=b.value});
  var d=$('dlDir');MAP.forEach(function(m){var a=$(m[0]);if(a)a.placeholder=(d&&d.value)?d.value:t('st_def')})}
 function push(i){var a=$(MAP[i][0]),b=$(MAP[i][1]);b.value=a.value.trim();save()}
 async function pick(i,btn){var a=$(MAP[i][0]);btn.disabled=true;
  try{var r=await api('pickfolder',{});var tries=0;while(r&&r.busy&&tries++<600){await new Promise(function(z){setTimeout(z,1000)});r=await api('pickfolder')}
   if(r&&r.path){a.value=r.path;push(i)}}catch(e){}finally{btn.disabled=false}}
 MAP.forEach(function(m,i){var a=$(m[0]);if(!a)return;a.addEventListener('change',function(){push(i)});$(m[2]).onclick=function(){pick(i,this)}});
 setInterval(pull,1000);setTimeout(pull,300);
 var _al3=applyLang;applyLang=function(){_al3.apply(this,arguments);pull()};
})();
