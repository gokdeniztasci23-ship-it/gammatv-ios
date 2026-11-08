/* GammaTV iPhone koprusu: masaustundeki pywebview arayuzunun yerini tutar.
   Sayfa gammatv://app adresinden yuklenir; /bilgi, /p ve /onbellek (okuma) istekleri uygulamanin aktaricisina gider.
   Kayit, onbellege yazma, tam ekran ve sistem cubugu renkleri window.webkit.messageHandlers.gamma ile yapilir. */
window.IOS=true;
/* Xtream canli yayin adresi (.../kullanici/sifre/123 ya da .ts) -> iPhone'un kendi oynaticisinin actigi .m3u8 karsiligi */
window.xtreamHls=u=>{const m=String(u||"").match(/^(https?:\/\/[^\/?#]+)\/(?:live\/)?([^\/?#]+)\/([^\/?#]+)\/(\d+)(?:\.ts)?(?:\?.*)?$/i);
  return m?m[1]+"/live/"+m[2]+"/"+m[3]+"/"+m[4]+".m3u8":""};
(function(){
  const M=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.gamma;if(!M)return;
  const ist=(k,a)=>M.postMessage(Object.assign({k},a||{}));
  window.pywebview={api:{
    yukle:async()=>{try{return JSON.parse(await ist("yukle")||"{}")}catch(e){return{}}},
    kaydet:async v=>{try{await ist("kaydet",{v:JSON.stringify(v)})}catch(e){}return true},
    tam_ekran:async a=>{try{return await ist("tamEkran",{a:!!a})}catch(e){return!!a}}}};
  const asil=window.fetch.bind(window);
  window.fetch=async function(g,a){a=a||{};const u=typeof g==="string"?g:(g&&g.url)||"",m=(a.method||"GET").toUpperCase();
    if(u.startsWith("/onbellek/")&&m!=="GET"){const id=u.slice(10).split("?")[0];
      if(m==="POST")await ist("onbYaz",{id,t:typeof a.body==="string"?a.body:await new Response(a.body).text()});
      else await ist("onbSil",{id});
      return new Response("")}
    return asil(g,a)};
  const st=document.createElement("style");st.textContent=".satir:has(#aRtx),.rtx-rozet{display:none!important}";document.head.append(st);
  /* sistem cubuklari: ustteki durum cubugu ve alttaki ev cubugu alani sayfanin o anki zemin rengine boyanir */
  const hex=c=>{const m=String(c||"").match(/[\d.]+/g);if(!m||m.length<3||(m.length>3&&+m[3]<1))return null;
    return"#"+m.slice(0,3).map(x=>Math.round(+x).toString(16).padStart(2,"0")).join("")};
  const zemin=el=>{for(;el&&el.nodeType===1;el=el.parentElement){const h=hex(getComputedStyle(el).backgroundColor);if(h)return h}return"#000000"};
  const acikMi=h=>{const n=parseInt(h.slice(1),16);return .299*(n>>16)+.587*(n>>8&255)+.114*(n&255)>150};
  const dikey=matchMedia("(max-width:760px) and (orientation:portrait)");let son="",zmn=0;
  const guncelle=()=>{const b=document.body;if(!b||b.classList.contains("sinema"))return;
    const intro=document.getElementById("intro"),u=document.getElementById("uygulama"),l=document.querySelector(".liste");let ust,alt;
    if(intro&&intro.isConnected&&!intro.dataset.cikis)ust=alt=zemin(intro);
    else{ust=zemin(b);alt=dikey.matches&&l&&u&&!u.classList.contains("liste-yok")?zemin(l):ust}
    const t=document.documentElement.dataset.tema||"",acilis=t==="acik"?"#ffffff":t==="koyu"?"#000000":"";
    const s=ust+alt+acilis;if(s!==son){son=s;ist("cubuk",{ust,alt,acik:acikMi(ust),acilis}).catch(()=>{})}};
  const planla=()=>{guncelle();clearTimeout(zmn);zmn=setTimeout(guncelle,450)};
  window.__cubuk=planla;
  document.addEventListener("DOMContentLoaded",()=>{const g=new MutationObserver(planla);
    g.observe(document.documentElement,{attributes:true,attributeFilter:["data-tema"]});
    g.observe(document.body,{attributes:true,attributeFilter:["class"]});
    const u=document.getElementById("uygulama");if(u)g.observe(u,{attributes:true,attributeFilter:["class"]});
    const i=document.getElementById("intro");
    if(i){i.addEventListener("animationstart",e=>{if(e.target===i&&e.animationName==="introCik"){i.dataset.cikis="1";planla()}});
      const c=new MutationObserver(()=>{if(!i.isConnected){c.disconnect();planla()}});c.observe(document.body,{childList:true})}
    matchMedia("(prefers-color-scheme:dark)").addEventListener("change",planla);
    dikey.addEventListener("change",planla);addEventListener("resize",planla);
    /* iPhone'da Managed Media Source icin AirPlay uzaktan oynatma kapali olmali */
    const v=document.querySelector("video");if(v){v.disableRemotePlayback=true;v.setAttribute("playsinline","")}
    planla()})
})();
