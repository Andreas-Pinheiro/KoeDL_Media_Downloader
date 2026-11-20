/* patrocinador discreto: le ads.json do GitHub (sem rastreio, sem script de terceiros). Falhou/offline = nada aparece. */
(function(){
 var URL_ADS='https://raw.githubusercontent.com/Andreas-Pinheiro/KoeDL_Media_Downloader/main/ads.json',bar=null,closed=false;
 try{closed=sessionStorage.getItem('adx')==='1'}catch(e){}
 function lang(){try{return LANG==='en'?'en':'pt'}catch(e){return 'pt'}}
 function pick(list){var now=Date.now(),ok=(list||[]).filter(function(a){
   if(!a||!a.url||!/^https:\/\//i.test(a.url))return false;var txt=a.text&&(a.text[lang()]||a.text.pt||a.text.en);if(!txt)return false;
   if(a.from&&Date.parse(a.from)>now)return false;if(a.to&&Date.parse(a.to)+864e5<now)return false;return true});
  if(!ok.length)return null;var tot=ok.reduce(function(s,a){return s+(a.weight>0?a.weight:1)},0),r=Math.random()*tot;
  for(var i=0;i<ok.length;i++){r-=(ok[i].weight>0?ok[i].weight:1);if(r<=0)return ok[i]}return ok[0]}
 function ensure(){if(bar)return bar;var f=document.querySelector('footer');if(!f)return null;
  bar=document.createElement('div');bar.id='adbar';bar.innerHTML='<span class="adl"></span><a role="link" tabindex="0"></a><button type="button" aria-label=""></button>';
  bar.querySelector('button').textContent='×';bar.querySelector('button').onclick=function(){closed=true;try{sessionStorage.setItem('adx','1')}catch(e){}hide()};
  f.parentNode.insertBefore(bar,f);return bar}
 function hide(){if(bar)bar.classList.remove('on')}
 async function show(){var cb=document.getElementById('showAds');if(closed||(cb&&!cb.checked)){hide();return}
  try{var c=new AbortController(),tm=setTimeout(function(){c.abort()},4000),r=await fetch(URL_ADS,{cache:'no-cache',signal:c.signal});clearTimeout(tm);
   if(!r.ok)return;var j=await r.json(),a=pick(j.ads);if(!a){hide();return}var b=ensure();if(!b)return;
   b.querySelector('.adl').textContent=t('ads_lbl');b.querySelector('button').setAttribute('aria-label',t('ads_x'));
   var an=b.querySelector('a');an.textContent=a.text[lang()]||a.text.pt||a.text.en;an.setAttribute('data-href',a.url);an.title=a.url;b.classList.add('on')}catch(e){hide()}}
 window.addEventListener('load',function(){setTimeout(show,2500)});
 document.addEventListener('change',function(e){if(e.target&&e.target.id==='showAds')show()});
})();
